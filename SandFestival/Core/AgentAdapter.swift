import Foundation

/// The contract every concrete agent implementation honors. The MVP ships
/// only a Claude Code adapter, but any future adapter (Aider, Codex, etc.)
/// plugs in through this same boundary.
@MainActor
protocol AgentAdapter: AnyObject {
    static var id: String { get }
    static var displayName: String { get }

    var defaultCommand: String { get }
    var defaultArgs: [String] { get }

    /// Extra agent args (placed after the `--` separator) that make the agent
    /// resume its previous conversation instead of starting fresh. Empty when
    /// the agent has no such concept; Claude Code returns `["--continue"]`.
    /// `Session.startContinuing()` appends these via `Session.composeArgs`.
    var continuationArgs: [String] { get }

    /// Called once at app startup. The adapter does whatever setup it needs
    /// and routes future observations through `eventSink`.
    func start(eventSink: AgentEventSink) async throws

    /// Called on app shutdown or when the user explicitly disconnects.
    func stop() async

    /// Called immediately before a session is spawned. The adapter returns
    /// any environment additions it wants merged onto the spawn env, and may
    /// also register pre-spawn routing state — the Claude Code adapter binds
    /// `(projectID, cwd)` here so the SessionStart hook can resolve to a
    /// project even if it fires before `didSpawnSession` runs.
    func prepareSpawn(project: Project) -> SpawnEnvironment

    /// Called once a session has been spawned. Adapters that need post-spawn
    /// state (e.g. starting a timer once the process is alive) can hook in
    /// here; routing setup that must survive the very first hook fire
    /// belongs in `prepareSpawn` instead.
    func didSpawnSession(_ session: SessionHandle)

    /// Called immediately before a session terminates so the adapter can
    /// release any per-session bindings.
    func willTerminateSession(_ session: SessionHandle)
}

extension AgentAdapter {
    /// Most agents have no resume concept; opt in by overriding.
    var continuationArgs: [String] { [] }
}
