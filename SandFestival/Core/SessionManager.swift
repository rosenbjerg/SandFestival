import Foundation
import Observation

@MainActor
@Observable
final class SessionManager {
    private(set) var projects: [Project] = []
    private(set) var sessions: [Project.ID: Session] = [:]
    var selectedProjectID: Project.ID?
    private(set) var lastPersistError: String?

    @ObservationIgnored private let store: ProjectStore
    @ObservationIgnored private(set) var adapter: (any AgentAdapter)?
    @ObservationIgnored private var router: AgentEventRouter?

    init(store: ProjectStore? = nil) {
        let resolvedStore = store ?? ProjectStore()
        self.store = resolvedStore
        do {
            projects = try resolvedStore.load()
        } catch {
            projects = []
        }
        for project in projects {
            sessions[project.id] = Session(project: project)
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
        sessions[project.id] = Session(project: project)
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

    func startSession(id: Project.ID) {
        guard let session = sessions[id] else { return }
        let extraEnv = adapter?.prepareSpawn(project: session.project).additions ?? [:]
        session.start(extraEnvironment: extraEnv)
        adapter?.didSpawnSession(handle(for: session.project))
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
        if !session.state.isRunning {
            // restart is asynchronous when the session is currently running:
            // we'll need to register the new spawn after it completes. For
            // now, didSpawnSession is only emitted on the synchronous path.
            adapter?.didSpawnSession(handle(for: project))
        }
    }

    // MARK: - Matcher resolution

    func resolveProjectID(_ matcher: SessionMatcher) -> Project.ID? {
        switch matcher {
        case .projectID(let id):
            return projects.contains(where: { $0.id == id }) ? id : nil
        case .workingDirectory(let url):
            let target = url.standardizedFileURL.path
            return projects.first { $0.path.standardizedFileURL.path == target }?.id
        case .sessionID, .pid:
            return nil
        }
    }

    // MARK: - Internal

    private func autoStartIfNeeded() {
        for project in projects where project.autoStart {
            startSession(id: project.id)
        }
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
