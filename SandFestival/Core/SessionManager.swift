import Foundation
import Observation

@MainActor
@Observable
final class SessionManager {
    private(set) var projects: [Project] = []
    private(set) var sessions: [Project.ID: Session] = [:]
    var selectedProjectID: Project.ID?

    @ObservationIgnored private let store: ProjectStore

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
        autoStartIfNeeded()
    }

    // MARK: - CRUD

    func addProject(_ project: Project) {
        projects.append(project)
        sessions[project.id] = Session(project: project)
        selectedProjectID = project.id
        persist()
        if project.autoStart {
            sessions[project.id]?.start()
        }
    }

    func updateProject(_ project: Project) {
        guard let index = projects.firstIndex(where: { $0.id == project.id }) else { return }
        projects[index] = project
        sessions[project.id]?.update(project: project)
        persist()
    }

    func removeProject(id: Project.ID) {
        sessions[id]?.stop()
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
        sessions[id]?.start()
    }

    func stopSession(id: Project.ID) {
        sessions[id]?.stop()
    }

    func restartSession(id: Project.ID) {
        sessions[id]?.restart()
    }

    // MARK: - Internal

    private func autoStartIfNeeded() {
        for project in projects where project.autoStart {
            sessions[project.id]?.start()
        }
    }

    private func persist() {
        do {
            try store.save(projects)
        } catch {
            // Surface persistence failures via a banner in a follow-up step;
            // for now, silently swallow so a transient write failure doesn't
            // crash the app.
        }
    }
}
