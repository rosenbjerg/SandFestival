import Foundation

@MainActor
final class AgentEventRouter: AgentEventSink {
    private weak var manager: SessionManager?

    init(manager: SessionManager) {
        self.manager = manager
    }

    func report(matching matcher: SessionMatcher, event: AgentEvent) {
        guard let manager else { return }
        guard let projectID = manager.resolveProjectID(matcher) else { return }
        manager.session(for: projectID)?.apply(event: event)
    }

    func updateMetadata(matching matcher: SessionMatcher, metadata: AgentMetadata) {
        guard let manager else { return }
        guard let projectID = manager.resolveProjectID(matcher) else { return }
        manager.session(for: projectID)?.updateMetadata(metadata)
    }
}
