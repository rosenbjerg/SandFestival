import Foundation

/// Interface adapters use to push observations back into the core. Adapters
/// own whatever mapping they need from agent-side identifiers (cwd,
/// session_id, PID, etc.) to the project — by the time they call the sink,
/// they already know which Project the event belongs to.
@MainActor
protocol AgentEventSink: AnyObject {
    func report(projectID: Project.ID, event: AgentEvent)
}
