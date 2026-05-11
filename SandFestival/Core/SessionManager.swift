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

    static let defaultFontSize: CGFloat = 13
    static let minFontSize: CGFloat = 9
    static let maxFontSize: CGFloat = 32
    private static let fontSizeKey = "terminal.fontSize"

    @ObservationIgnored private let store: ProjectStore
    @ObservationIgnored private(set) var adapter: (any AgentAdapter)?
    @ObservationIgnored private var router: AgentEventRouter?

    /// Forwards every real session state transition (`from`, `to`) to a
    /// single subscriber — owned by the App layer and used by
    /// `AttentionNotifier` to drive dock badge / bounce / notifications.
    /// Single observer is fine: only one component cares cross-session today,
    /// and a one-to-one closure beats a publisher for this scope.
    @ObservationIgnored var sessionStateObserver: ((Session, SessionState, SessionState) -> Void)?

    init(store: ProjectStore? = nil) {
        let resolvedStore = store ?? ProjectStore()
        self.store = resolvedStore

        UserDefaults.standard.register(defaults: [
            SessionManager.fontSizeKey: Double(SessionManager.defaultFontSize),
        ])
        let storedFontSize = CGFloat(UserDefaults.standard.double(forKey: SessionManager.fontSizeKey))
        terminalFontSize = SessionManager.clampFontSize(storedFontSize)

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
        projects.append(project)
        sessions[project.id] = makeSession(for: project)
        selectedProjectID = project.id
        persist()
        if project.autoStart {
            startSession(id: project.id)
        }
    }

    func updateProject(_ project: Project) {
        guard let index = projects.firstIndex(where: { $0.id == project.id }) else { return }
        projects[index] = project
        sessions[project.id]?.update(project: project)
        persist()
    }

    func removeProject(id: Project.ID) {
        if let session = sessions[id], session.state.isRunning {
            session.stop()
        }
        if let project = projects.first(where: { $0.id == id }) {
            adapter?.willTerminateSession(handle(for: project))
        }
        sessions.removeValue(forKey: id)
        projects.removeAll { $0.id == id }
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
    /// Used by the menu bar label, the menu bar drop-down list, and the
    /// dock-badge / bounce logic in AttentionNotifier so all three surfaces
    /// stay in agreement about what "needs attention" means.
    var attentionSessions: [Session] {
        projects.compactMap { sessions[$0.id] }
            .filter { $0.state.needsAttention }
    }

    /// Selects a project and brings the app to the front. The menu bar list,
    /// the notification-tap handler, and any future deep-link entry point
    /// route through here so the three-step (select / activate / front)
    /// dance lives in exactly one place.
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
            self.sessionStateObserver?(session, old, new)
        }
        return session
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

    private func handle(for project: Project) -> SessionHandle {
        SessionHandle(projectID: project.id, workingDirectory: project.path)
    }

    private func persist() {
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
