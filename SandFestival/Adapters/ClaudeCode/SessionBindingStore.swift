import Foundation

/// Tracks Claude Code session_id ↔ Project.ID bindings. SandFestival injects a
/// per-spawn `SAND_FESTIVAL_PROJECT_ID` into the agent's environment and the
/// hook command forwards it as a header, so every SessionStart already names
/// its owning project. On spawn we record a "pending" entry keyed by that
/// project id; the first SessionStart consumes it (a fresh spawn). A later
/// SessionStart for a still-live project — e.g. after `/resume` or `/clear`,
/// which mint a new session_id while the same OS process keeps running —
/// rebinds the new session_id to the same project.
///
/// Routing by project id rather than cwd is what lets two projects share a
/// working directory (a "Duplicate…" without a worktree points the child at
/// the parent's path) without their sessions colliding: the env-injected id is
/// unique per project even when the cwd is not.
@MainActor
final class SessionBindingStore {
    /// Projects awaiting their first SessionStart after a SandFestival spawn.
    private var pendingSpawns: Set<UUID> = []
    /// Projects with a live OS process. Survives until `unbindAll(projectID:)`
    /// runs from process-termination cleanup, so `/resume`/`/clear` can rebind
    /// while a stray hook fired after the process dies is dropped.
    private var liveProjects: Set<UUID> = []
    private var sessionToProject: [String: UUID] = [:]

    func registerPendingSpawn(projectID: UUID) {
        pendingSpawns.insert(projectID)
        liveProjects.insert(projectID)
    }

    func clearPendingSpawn(projectID: UUID) {
        pendingSpawns.remove(projectID)
    }

    /// Binds a Claude `session_id` for the SessionStart hook, given the
    /// owning project id carried by the spawn-injected header. The first
    /// SessionStart after a spawn consumes the pending entry; a later
    /// SessionStart for a still-live project (e.g. after `/resume` or
    /// `/clear`) rebinds to it. The outcome distinguishes the two so callers
    /// can react differently (e.g. clearing per-conversation state on a
    /// rebind). A SessionStart for a project that was never spawned or has
    /// already terminated resolves to `nil` and is dropped.
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
        pendingSpawns.remove(projectID)
        liveProjects.remove(projectID)
    }
}
