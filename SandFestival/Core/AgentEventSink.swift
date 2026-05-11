import Foundation

/// Interface adapters use to push observations back into the core. Adapters
/// don't know which Project a hook event belongs to — they describe what they
/// know via the matcher and let the core resolve.
@MainActor
protocol AgentEventSink: AnyObject {
    func report(matching: SessionMatcher, event: AgentEvent)
}
