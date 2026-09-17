import Foundation

@MainActor
final class SessionBindingStore {
    private var pendingSpawns: Set<UUID> = []
    private var liveProjects: Set<UUID> = []
    private var sessionToProject: [String: UUID] = [:]

    func registerPendingSpawn(projectID: UUID) {
        pendingSpawns.insert(projectID)
        liveProjects.insert(projectID)
    }

    func clearPendingSpawn(projectID: UUID) {
        pendingSpawns.remove(projectID)
    }

    @discardableResult
    func bindOnSessionStart(sessionID: String, projectID: UUID) -> BindOutcome? {
        if pendingSpawns.remove(projectID) != nil {
            sessionToProject[sessionID] = projectID
            return .freshSpawn(projectID)
        }
        if liveProjects.contains(projectID) {
            sessionToProject[sessionID] = projectID
            return .rebound(projectID)
        }
        return nil
    }

    enum BindOutcome: Equatable {
        case freshSpawn(UUID)
        case rebound(UUID)
    }

    func projectID(forSession sessionID: String) -> UUID? {
        sessionToProject[sessionID]
    }

    func unbind(sessionID: String) {
        sessionToProject.removeValue(forKey: sessionID)
    }

    func unbindAll(projectID: UUID) {
        sessionToProject = sessionToProject.filter { $0.value != projectID }
        pendingSpawns.remove(projectID)
        liveProjects.remove(projectID)
    }
}
