import Foundation

@MainActor
protocol AgentAdapter: AnyObject {
    static var id: String { get }
    static var displayName: String { get }

    var defaultCommand: String { get }
    var defaultArgs: [String] { get }
    var continuationArgs: [String] { get }

    func start(eventSink: AgentEventSink) async throws
    func stop() async
    func prepareSpawn(project: Project) -> SpawnEnvironment
    func didSpawnSession(_ session: SessionHandle)
    func willTerminateSession(_ session: SessionHandle)
}

extension AgentAdapter {
    var continuationArgs: [String] { [] }
}
