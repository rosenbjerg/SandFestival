import Foundation

/// Tracks Claude Code session_id ↔ Project.ID bindings. On spawn we record a
/// "pending" entry keyed by cwd, and the first SessionStart hook for that
/// cwd consumes the entry and binds the session_id. We also keep a
/// "live cwds" entry that survives until the spawned process actually dies,
/// so `/resume` and `/clear` — which mint a new session_id while the same
/// OS process keeps running — can rebind to the same project.
@MainActor
final class SessionBindingStore {
    private var pendingSpawns: [String: UUID] = [:]
    private var liveProjectsByCwd: [String: UUID] = [:]
    private var sessionToProject: [String: UUID] = [:]

    func registerPendingSpawn(projectID: UUID, cwd: URL) {
        let key = Self.key(cwd: cwd)
        pendingSpawns[key] = projectID
        liveProjectsByCwd[key] = projectID
    }

    func clearPendingSpawn(projectID: UUID) {
        pendingSpawns = pendingSpawns.filter { $0.value != projectID }
    }

    /// Tries to bind a Claude `session_id` for the SessionStart hook. The
    /// first SessionStart after a spawn consumes the pending entry; later
    /// SessionStart events for the same cwd (e.g. after `/resume` or
    /// `/clear`) fall back to the live-projects map, which lives until
    /// `unbindAll(projectID:)` is called from process-termination cleanup.
    /// The outcome distinguishes the two so callers can react differently
    /// (e.g. clearing per-conversation state on a rebind).
    @discardableResult
    func bindOnSessionStart(sessionID: String, cwd: URL?) -> BindOutcome? {
        guard let cwd else { return nil }
        let key = Self.key(cwd: cwd)
        if let projectID = pendingSpawns.removeValue(forKey: key) {
            sessionToProject[sessionID] = projectID
            return .freshSpawn(projectID)
        }
        if let projectID = liveProjectsByCwd[key] {
            sessionToProject[sessionID] = projectID
            return .rebound(projectID)
        }
        return nil
    }

    enum BindOutcome: Equatable {
        /// First SessionStart after a SandFestival-initiated spawn —
        /// consumed the pending entry.
        case freshSpawn(UUID)
        /// A later SessionStart for an already-live project: `/resume` or
        /// `/clear` minted a new session_id while the OS process kept
        /// running.
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
        pendingSpawns = pendingSpawns.filter { $0.value != projectID }
        liveProjectsByCwd = liveProjectsByCwd.filter { $0.value != projectID }
    }

    /// Canonicalizes cwd before keying so the spawn-side and SessionStart-side
    /// hash to the same value even when one path traverses a symlink (e.g. a
    /// project rooted at `/Users/me/Code/foo` that's a link to
    /// `/Volumes/SSD/Code/foo` — Claude reports the resolved target while the
    /// app stores whatever the user picked). Without this, hook events for
    /// symlinked projects get silently dropped.
    private static func key(cwd: URL) -> String {
        cwd.resolvingSymlinksInPath().standardizedFileURL.path
    }
}
