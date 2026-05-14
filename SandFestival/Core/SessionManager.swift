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
    /// Opt-in flag mirroring SwiftTerm's `setUseMetal`. The GPU path can shave
    /// real CPU on busy multi-session setups but the SwiftTerm docs flag it as
    /// "still evolving" — we keep it off by default and let the user flip it
    /// from preferences.
    private(set) var useMetalRenderer: Bool = false

    static let defaultFontSize: CGFloat = 13
    static let minFontSize: CGFloat = 9
    static let maxFontSize: CGFloat = 32
    private static let fontSizeKey = "terminal.fontSize"

    /// Scrollback covers a few screens of Claude output without ballooning
    /// memory across many always-resident terminal views (DetailPaneView
    /// keeps every session's view in the hierarchy, so the cost is linear
    /// in project count).
    static let defaultScrollback: Int = 2_000
    static let minScrollback: Int = 500
    static let maxScrollback: Int = 50_000
    private static let scrollbackKey = "terminal.scrollback"
    private static let useMetalKey = "terminal.useMetal"

    @ObservationIgnored private let store: ProjectStore
    @ObservationIgnored private(set) var adapter: (any AgentAdapter)?
    @ObservationIgnored private var router: AgentEventRouter?

    /// Forwards every real session state transition (`from`, `to`) to a
    /// single subscriber — owned by the App layer and used by
    /// `AttentionNotifier` to drive dock badge / bounce / notifications.
    /// Single observer is fine: only one component cares cross-session today,
    /// and a one-to-one closure beats a publisher for this scope.
    @ObservationIgnored var sessionStateObserver: ((Session, SessionState, SessionState) -> Void)?

    /// Gates the "auto-surface to row 0 on Claude-driven activity" behavior.
    /// App layer wires this to AttentionPreferences so Core stays free of the
    /// preference type. Defaults to off — bare `SessionManager()` (and tests)
    /// see the previous behavior unless they opt in.
    @ObservationIgnored var shouldSurfaceOnActivity: () -> Bool = { false }

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

    /// Keeps the flat `projects` array in display order: a duplicate is
    /// inserted directly after the parent's existing children (so siblings
    /// stay adjacent), or right after the parent itself when there are
    /// none yet. Returns `nil` when the parent isn't in the list — caller
    /// falls back to a plain append, which also re-parents to top level on
    /// next render because the parent reference no longer resolves.
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

    /// Replaces the flat `projects` order with `newOrder` after sanity
    /// checks. Used by the sidebar's hierarchical drag-reorder, which
    /// computes the new order externally (moving parent + children as a
    /// block) and just hands the resulting array back here. The set of ids
    /// must match exactly — otherwise the call is a no-op so a malformed
    /// caller can't accidentally drop or duplicate projects.
    func replaceProjectsOrder(_ newOrder: [Project]) {
        guard newOrder.count == projects.count else { return }
        guard Set(newOrder.map(\.id)) == Set(projects.map(\.id)) else { return }
        projects = newOrder
        persist()
    }

    func removeProject(id: Project.ID) {
        if let session = sessions[id], session.state.isRunning {
            // Hard-kill: the project is going away, so nono's
            // post-kill confirmation prompt has no one to answer it.
            session.forceStop()
        }
        if let project = projects.first(where: { $0.id == id }) {
            adapter?.willTerminateSession(handle(for: project))
        }
        sessions.removeValue(forKey: id)
        projects.removeAll { $0.id == id }
        // Any duplicates of the removed project become top-level on their
        // own — preserve them rather than cascade-removing. The user can
        // delete them individually if they want, including the worktree
        // cleanup sheet.
        for index in projects.indices where projects[index].parentProjectID == id {
            projects[index].parentProjectID = nil
        }
        if selectedProjectID == id {
            selectedProjectID = projects.first?.id
        }
        persist()
    }

    // MARK: - Session control

    func session(for id: Project.ID) -> Session? {
        sessions[id]
    }

    func selectedSession() -> Session? {
        guard let id = selectedProjectID else { return nil }
        return sessions[id]
    }

    /// Live sessions whose state needs the user's attention, in sidebar order.
    /// Used by the dock-badge / bounce logic in AttentionNotifier so the
    /// sidebar and notifications stay in agreement about what "needs
    /// attention" means.
    var attentionSessions: [Session] {
        projects.compactMap { sessions[$0.id] }
            .filter { $0.state.needsAttention }
    }

    /// Selects a project and brings the app to the front. The
    /// notification-tap handler and any future deep-link entry point route
    /// through here so the three-step (select / activate / front) dance
    /// lives in exactly one place.
    func focus(projectID: Project.ID) {
        selectedProjectID = projectID
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first?.makeKeyAndOrderFront(nil)
    }

    /// Makes the selected session's terminal the window's first responder so
    /// keystrokes land in the PTY immediately. Scheduled on the next runloop
    /// tick because callers (app-activation, selection-change) fire before
    /// the window has finished settling its responder chain.
    func focusSelectedTerminal() {
        guard let session = selectedSession() else { return }
        DispatchQueue.main.async {
            session.terminalView.window?.makeFirstResponder(session.terminalView)
        }
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

    // MARK: - Matcher resolution

    func resolveProjectID(_ matcher: SessionMatcher) -> Project.ID? {
        switch matcher {
        case .projectID(let id):
            return projects.contains(where: { $0.id == id }) ? id : nil
        case .workingDirectory(let url):
            let target = url.standardizedFileURL.path
            return projects.first { $0.path.standardizedFileURL.path == target }?.id
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
        // Provider rather than a snapshot so a session created before the user
        // flips the preference still applies the latest value when its view
        // enters a window. `applyMetalRenderer` handles live transitions for
        // sessions already on screen.
        session.terminalView.useMetalProvider = { [weak self] in
            self?.useMetalRenderer ?? false
        }
        // Pure black + ANSI "white" (≈ light gray) is what makes plain text
        // look dull. A near-black background (Terminal.app's Pro theme is
        // similar) and an off-white default foreground push contrast back up
        // for non-styled output without affecting Claude Code's own ANSI
        // colors.
        session.terminalView.nativeBackgroundColor = NSColor(white: 0.11, alpha: 1.0)
        session.terminalView.nativeForegroundColor = NSColor(white: 0.94, alpha: 1.0)
        session.spawnEnvProvider = { [weak self] project in
            self?.adapter?.prepareSpawn(project: project).additions ?? [:]
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
        }
        return session
    }

    /// Lifts `projectID` to row 0 when Claude reports activity worth surfacing,
    /// gated on the user's preference. State equality is already guaranteed by
    /// `Session.transition` (which is the only caller of `onStateChanged`), so
    /// "burst" duplicates from same-state events can't reach here. The in-memory
    /// move is immediate; the disk write is debounced so a flurry of transitions
    /// coalesces into one `projects.json` write.
    private func surfaceIfActivityTrigger(projectID: Project.ID, to state: SessionState) {
        guard shouldSurfaceOnActivity() else { return }
        guard SessionManager.isActivitySurfaceTrigger(state) else { return }
        guard let index = projects.firstIndex(where: { $0.id == projectID }), index != 0 else { return }
        let project = projects.remove(at: index)
        projects.insert(project, at: 0)
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

    private func currentTerminalFont() -> NSFont {
        // .medium reads noticeably crisper than .regular on dark backgrounds
        // — the slightly thicker stroke survives anti-aliasing better.
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

    /// Flips the SwiftTerm Metal renderer on every live session. `try?` because
    /// `setUseMetal` throws on hosts without a Metal device — silently falling
    /// back to CoreGraphics matches what `viewDidMoveToWindow` does for new
    /// sessions and avoids surfacing an error path users can't act on.
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
