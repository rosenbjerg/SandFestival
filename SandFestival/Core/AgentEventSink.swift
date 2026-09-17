import Foundation

@MainActor
protocol AgentEventSink: AnyObject {
    func report(projectID: Project.ID, event: AgentEvent)
}
