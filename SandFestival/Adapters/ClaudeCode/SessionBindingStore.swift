import Foundation

/// Tracks Claude Code session_id ↔ Project.ID bindings. On spawn we record a
/// "pending" entry keyed by cwd, and the first SessionStart hook for that
/// cwd consumes the entry and binds the session_id.
@MainActor
final class SessionBindingStore {
    private var pendingSpawns: [String: UUID] = [:]
    private var sessionToProject: [String: UUID] = [:]

    func registerPendingSpawn(projectID: UUID, cwd: URL) {
        pendingSpawns[Self.key(cwd: cwd)] = projectID
    }

    func clearPendingSpawn(projectID: UUID) {
        pendingSpawns = pendingSpawns.filter { $0.value != projectID }
    }

    /// Tries to bind a Claude `session_id` for the SessionStart hook by
    /// matching its cwd against pending spawns. Returns the resolved
    /// project ID or `nil` if no spawn was waiting.
    @discardableResult
    func bindOnSessionStart(sessionID: String, cwd: URL?) -> UUID? {
        guard let cwd, let projectID = pendingSpawns[Self.key(cwd: cwd)] else {
            return nil
        }
        sessionToProject[sessionID] = projectID
        pendingSpawns.removeValue(forKey: Self.key(cwd: cwd))
        return projectID
    }

    func projectID(forSession sessionID: String) -> UUID? {
        sessionToProject[sessionID]
    }

    func unbind(sessionID: String) {
        sessionToProject.removeValue(forKey: sessionID)
    }

    func unbindAll(projectID: UUID) {
        sessionToProject = sessionToProject.filter { $0.value != projectID }
        pendingSpawns = pendingSpawns.filter { $0.value != projectID }
    }

    private static func key(cwd: URL) -> String {
        cwd.standardizedFileURL.path
    }
}
