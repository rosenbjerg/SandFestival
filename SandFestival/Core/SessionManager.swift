import AppKit
import Foundation
import Observation
import SwiftTerm

@MainActor
@Observable
final class SessionManager {
    private(set) var projects: [Project] = []
    private(set) var sessions: [Project.ID: Session] = [:]
    var selectedProjectID: Project.ID?
    private(set) var lastPersistError: String?
    private(set) var terminalFontSize: CGFloat = SessionManager.defaultFontSize
    private(set) var terminalScrollback: Int = SessionManager.defaultScrollback
    private(set) var useMetalRenderer: Bool = false

    static let defaultFontSize: CGFloat = 13
    static let minFontSize: CGFloat = 9
    static let maxFontSize: CGFloat = 32
    private static let fontSizeKey = "terminal.fontSize"

    static let defaultScrollback: Int = 2_000
    static let minScrollback: Int = 500
    static let maxScrollback: Int = 50_000
    private static let scrollbackKey = "terminal.scrollback"
    private static let useMetalKey = "terminal.useMetal"

    @ObservationIgnored private let store: ProjectStore
    @ObservationIgnored private(set) var adapter: (any AgentAdapter)?
    @ObservationIgnored private var router: AgentEventRouter?

    @ObservationIgnored var sessionStateObserver: ((Session, SessionState, SessionState) -> Void)?
    @ObservationIgnored var sessionDidFinishWork: ((Project) -> Void)?
    @ObservationIgnored var anyWorkingDidChange: ((Bool) -> Void)?
    @ObservationIgnored private var anyWorking = false
    @ObservationIgnored var shouldSurfaceOnActivity: () -> Bool = { false }
    @ObservationIgnored var isAppActive: () -> Bool = { NSApp.isActive }

    @ObservationIgnored private var persistDebounceTask: Task<Void, Never>?
    @ObservationIgnored var persistDebounceDelay: Duration = .seconds(1)

    init(store: ProjectStore? = nil) {
        let resolvedStore = store ?? ProjectStore()
        self.store = resolvedStore

        UserDefaults.standard.register(defaults: [
            SessionManager.fontSizeKey: Double(SessionManager.defaultFontSize),
            SessionManager.scrollbackKey: SessionManager.defaultScrollback,
            SessionManager.useMetalKey: false,
        ])
        let storedFontSize = CGFloat(UserDefaults.standard.double(forKey: SessionManager.fontSizeKey))
        terminalFontSize = SessionManager.clampFontSize(storedFontSize)
        let storedScrollback = UserDefaults.standard.integer(forKey: SessionManager.scrollbackKey)
        terminalScrollback = SessionManager.clampScrollback(storedScrollback)
        useMetalRenderer = UserDefaults.standard.bool(forKey: SessionManager.useMetalKey)

        do {
            projects = try resolvedStore.load()
        } catch {
            projects = []
        }
        for project in projects {
            sessions[project.id] = makeSession(for: project)
        }
        if let first = projects.first {
            selectedProjectID = first.id
        }
    }

    // MARK: - Adapter binding

    func attach(adapter: any AgentAdapter) async throws {
        guard self.adapter == nil else { return }
        self.adapter = adapter
        let router = AgentEventRouter(manager: self)
        self.router = router
        try await adapter.start(eventSink: router)
        autoStartIfNeeded()
    }

    func detachAdapter() async {
        await adapter?.stop()
        adapter = nil
        router = nil
    }

    // MARK: - CRUD

    func addProject(_ project: Project) {
        if let parentID = project.parentProjectID,
           let insertIndex = insertionIndex(forChildOf: parentID) {
            projects.insert(project, at: insertIndex)
        } else {
            projects.append(project)
        }
        sessions[project.id] = makeSession(for: project)
        selectedProjectID = project.id
        persist()
        if project.autoStart {
            startSession(id: project.id)
        }
    }

    private func insertionIndex(forChildOf parentID: Project.ID) -> Int? {
        guard let parentIndex = projects.firstIndex(where: { $0.id == parentID }) else { return nil }
        var insertAt = parentIndex + 1
        while insertAt < projects.count && projects[insertAt].parentProjectID == parentID {
            insertAt += 1
        }
        return insertAt
    }

    func updateProject(_ project: Project) {
        guard let index = projects.firstIndex(where: { $0.id == project.id }) else { return }
        projects[index] = project
        sessions[project.id]?.update(project: project)
        persist()
    }

    func moveProjects(fromOffsets source: IndexSet, toOffset destination: Int) {
        let moving = source.map { projects[$0] }
        var remaining = projects
        for index in source.sorted(by: >) {
            remaining.remove(at: index)
        }
        let shift = source.filter { $0 < destination }.count
        remaining.insert(contentsOf: moving, at: destination - shift)
        projects = remaining
        persist()
    }

    func replaceProjectsOrder(_ newOrder: [Project]) {
        guard newOrder.count == projects.count else { return }
        guard Set(newOrder.map(\.id)) == Set(projects.map(\.id)) else { return }
        projects = newOrder
        persist()
    }

    func removeProject(id: Project.ID) {
        let removedSession = sessions[id]
        if let project = projects.first(where: { $0.id == id }) {
            adapter?.willTerminateSession(handle(for: project))
        }
        sessions.removeValue(forKey: id)
        refreshAnyWorking()
        projects.removeAll { $0.id == id }
        for index in projects.indices where projects[index].parentProjectID == id {
            projects[index].parentProjectID = nil
        }
        if selectedProjectID == id {
            selectedProjectID = projects.first?.id
        }
        persist()
        // Hold the Session through the kill: its terminal view must outlive it
        // for SwiftTerm's exit monitor to reap the child.
        if let removedSession {
            Task { await removedSession.forceStopAndWait() }
        }
    }

    // MARK: - Session control

    func terminateSessionAndWait(id: Project.ID, timeout: Duration = .seconds(5)) async -> Bool {
        guard let session = sessions[id] else { return true }
        if let project = projects.first(where: { $0.id == id }) {
            adapter?.willTerminateSession(handle(for: project))
        }
        return await session.forceStopAndWait(timeout: timeout)
    }

    func session(for id: Project.ID) -> Session? {
        sessions[id]
    }

    func selectedSession() -> Session? {
        guard let id = selectedProjectID else { return nil }
        return sessions[id]
    }

    var attentionSessions: [Session] {
        projects.compactMap { sessions[$0.id] }
            .filter { $0.state.needsAttention }
    }

    func focus(projectID: Project.ID) {
        selectedProjectID = projectID
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first?.makeKeyAndOrderFront(nil)
    }

    func focusSelectedTerminal() {
        guard let session = selectedSession() else { return }
        // Next tick: callers fire before the window has settled its responder chain.
        DispatchQueue.main.async {
            session.terminalView.window?.makeFirstResponder(session.terminalView)
        }
    }

    func markSelectedSessionSeen() {
        selectedSession()?.markOutputSeen()
    }

    func startSession(id: Project.ID) {
        sessions[id]?.start()
    }

    func stopSession(id: Project.ID) {
        guard let session = sessions[id], let project = projects.first(where: { $0.id == id }) else { return }
        adapter?.willTerminateSession(handle(for: project))
        session.stop()
    }

    func restartSession(id: Project.ID) {
        guard let session = sessions[id], let project = projects.first(where: { $0.id == id }) else { return }
        if session.state.isRunning {
            adapter?.willTerminateSession(handle(for: project))
        }
        session.restart()
    }

    func restartAllRunningContinuing() {
        for project in projects {
            guard let session = sessions[project.id], session.state.isRunning else { continue }
            adapter?.willTerminateSession(handle(for: project))
            session.restartContinuing()
        }
    }

    // MARK: - Internal

    private func autoStartIfNeeded() {
        for project in projects where project.autoStart {
            startSession(id: project.id)
        }
    }

    private func makeSession(for project: Project) -> Session {
        let session = Session(project: project)
        session.terminalView.font = currentTerminalFont()
        session.terminalView.getTerminal().changeScrollback(terminalScrollback)
        session.terminalView.useMetalProvider = { [weak self] in
            self?.useMetalRenderer ?? false
        }
        session.terminalView.nativeBackgroundColor = NSColor(white: 0.11, alpha: 1.0)
        session.terminalView.nativeForegroundColor = NSColor(white: 0.94, alpha: 1.0)
        session.spawnEnvProvider = { [weak self] project in
            self?.adapter?.prepareSpawn(project: project).additions ?? [:]
        }
        session.continuationArgsProvider = { [weak self] in
            self?.adapter?.continuationArgs ?? []
        }
        session.onDidSpawn = { [weak self] project in
            guard let self else { return }
            self.adapter?.didSpawnSession(self.handle(for: project))
        }
        session.onDidTerminate = { [weak self] project in
            guard let self else { return }
            self.adapter?.willTerminateSession(self.handle(for: project))
        }
        session.onStateChanged = { [weak self, weak session] old, new in
            guard let self, let session else { return }
            self.surfaceIfActivityTrigger(projectID: session.id, to: new)
            self.sessionStateObserver?(session, old, new)
            self.notifyIfWorkFinished(projectID: session.id, from: old, to: new)
            self.refocusIfStartTransition(projectID: session.id, from: old, to: new)
            self.trackUnseenOutput(session: session, from: old, to: new)
            self.refreshAnyWorking()
        }
        return session
    }

    private func refreshAnyWorking() {
        let now = sessions.values.contains { $0.state == .working }
        guard now != anyWorking else { return }
        anyWorking = now
        anyWorkingDidChange?(now)
    }

    private func trackUnseenOutput(session: Session, from old: SessionState, to new: SessionState) {
        if old == .idle {
            session.markOutputSeen()
        }
        guard AttentionEvent.from(transition: old, to: new) == .finishedOutputting else { return }
        let isViewed = session.id == selectedProjectID && isAppActive()
        if !isViewed {
            session.markOutputUnseen()
        }
    }

    // When the not-running overlay leaves the hierarchy AppKit doesn't promote
    // the terminal to first responder, so the next keystroke would go nowhere.
    private func refocusIfStartTransition(projectID: Project.ID, from old: SessionState, to new: SessionState) {
        guard projectID == selectedProjectID else { return }
        guard !old.isRunning, new.isRunning else { return }
        focusSelectedTerminal()
    }

    private func notifyIfWorkFinished(projectID: Project.ID, from old: SessionState, to new: SessionState) {
        guard old == .working, new != .working else { return }
        guard let project = projects.first(where: { $0.id == projectID }) else { return }
        sessionDidFinishWork?(project)
    }

    private func surfaceIfActivityTrigger(projectID: Project.ID, to state: SessionState) {
        guard shouldSurfaceOnActivity() else { return }
        guard SessionManager.isActivitySurfaceTrigger(state) else { return }
        guard let triggered = projects.first(where: { $0.id == projectID }) else { return }
        // Lift the whole parent block: moving a lone child splits it from its
        // parent in the flat array.
        let anchorID = triggered.parentProjectID ?? triggered.id
        guard let anchorIndex = projects.firstIndex(where: { $0.id == anchorID }),
              anchorIndex != 0
        else { return }
        let block = [projects[anchorIndex]] + projects.filter { $0.parentProjectID == anchorID }
        let blockIDs = Set(block.map(\.id))
        projects.removeAll { blockIDs.contains($0.id) }
        projects.insert(contentsOf: block, at: 0)
        schedulePersist()
    }

    static func isActivitySurfaceTrigger(_ state: SessionState) -> Bool {
        switch state {
        case .working, .waitingForPermission, .waitingForIdle, .errored:
            return true
        case .starting, .idle, .blockedByAutoMode, .stopped:
            return false
        }
    }

    private func schedulePersist() {
        persistDebounceTask?.cancel()
        let delay = persistDebounceDelay
        persistDebounceTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            self.persist()
        }
    }

    // MARK: - Terminal font size

    func bumpTerminalFontSize(by delta: CGFloat) {
        applyTerminalFontSize(SessionManager.clampFontSize(terminalFontSize + delta))
    }

    func resetTerminalFontSize() {
        applyTerminalFontSize(SessionManager.defaultFontSize)
    }

    private func applyTerminalFontSize(_ size: CGFloat) {
        let clamped = SessionManager.clampFontSize(size)
        guard clamped != terminalFontSize else { return }
        terminalFontSize = clamped
        UserDefaults.standard.set(Double(clamped), forKey: SessionManager.fontSizeKey)
        let font = currentTerminalFont()
        for session in sessions.values {
            session.terminalView.font = font
        }
    }

    func currentTerminalFont() -> NSFont {
        NSFont.monospacedSystemFont(ofSize: terminalFontSize, weight: .medium)
    }

    private static func clampFontSize(_ size: CGFloat) -> CGFloat {
        min(max(size, minFontSize), maxFontSize)
    }

    // MARK: - Terminal scrollback

    func applyTerminalScrollback(_ lines: Int) {
        let clamped = SessionManager.clampScrollback(lines)
        guard clamped != terminalScrollback else { return }
        terminalScrollback = clamped
        UserDefaults.standard.set(clamped, forKey: SessionManager.scrollbackKey)
        for session in sessions.values {
            session.terminalView.getTerminal().changeScrollback(clamped)
        }
    }

    private static func clampScrollback(_ lines: Int) -> Int {
        min(max(lines, minScrollback), maxScrollback)
    }

    // MARK: - GPU rendering

    func applyMetalRenderer(_ enabled: Bool) {
        guard enabled != useMetalRenderer else { return }
        useMetalRenderer = enabled
        UserDefaults.standard.set(enabled, forKey: SessionManager.useMetalKey)
        for session in sessions.values {
            try? session.terminalView.setUseMetal(enabled)
        }
    }

    private func handle(for project: Project) -> SessionHandle {
        SessionHandle(projectID: project.id, workingDirectory: project.path)
    }

    private func persist() {
        persistDebounceTask?.cancel()
        persistDebounceTask = nil
        do {
            try store.save(projects)
            lastPersistError = nil
        } catch {
            lastPersistError = error.localizedDescription
        }
    }

    func clearPersistError() {
        lastPersistError = nil
    }
}
