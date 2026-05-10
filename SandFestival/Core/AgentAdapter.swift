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

    /// Called once at app startup. The adapter does whatever setup it needs
    /// and routes future observations through `eventSink`.
    func start(eventSink: AgentEventSink) async throws

    /// Called on app shutdown or when the user explicitly disconnects.
    func stop() async

    /// Called immediately before a session is spawned. The adapter returns
    /// any environment additions it wants merged onto the spawn env.
    func prepareSpawn(project: Project) -> SpawnEnvironment

    /// Called once a session has been spawned, so the adapter can register
    /// the handle for routing future events.
    func didSpawnSession(_ session: SessionHandle)

    /// Called immediately before a session terminates so the adapter can
    /// release any per-session bindings.
    func willTerminateSession(_ session: SessionHandle)
}
