import Foundation

@MainActor
protocol AgentEventSink: AnyObject {
    func report(projectID: Project.ID, event: AgentEvent)
    func report(projectID: Project.ID, finishedTurnMessage message: String)
}
