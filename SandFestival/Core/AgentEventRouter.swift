import Foundation

@MainActor
final class AgentEventRouter: AgentEventSink {
    private weak var manager: SessionManager?

    init(manager: SessionManager) {
        self.manager = manager
    }

    func report(projectID: Project.ID, event: AgentEvent) {
        guard let manager else { return }
        // Drop reports for projects the user has since removed — the adapter
        // may still have an in-flight binding for them.
        guard let session = manager.session(for: projectID) else { return }
        session.apply(event: event)
    }
}
