import Foundation

@MainActor
final class AgentEventRouter: AgentEventSink {
    private weak var manager: SessionManager?

    init(manager: SessionManager) {
        self.manager = manager
    }

    func report(projectID: Project.ID, event: AgentEvent) {
        guard let manager else { return }
        guard let session = manager.session(for: projectID) else { return }
        session.apply(event: event)
    }

    func report(projectID: Project.ID, finishedTurnMessage message: String) {
        guard let manager, manager.summarizesTurns() else { return }
        guard let session = manager.session(for: projectID) else { return }
        session.summarizeTurn(message, with: manager.turnSummarizer())
    }
}
