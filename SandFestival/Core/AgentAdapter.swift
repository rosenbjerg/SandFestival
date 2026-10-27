import Foundation

@MainActor
protocol AgentAdapter: AnyObject {
    static var id: String { get }
    static var displayName: String { get }

    var defaultCommand: String { get }
    var defaultArgs: [String] { get }
    var continuationArgs: [String] { get }
    var acceptsPastedImagePaths: Bool { get }
    var transcriptRefinement: AgentTranscriptRefinement? { get }

    func start(eventSink: AgentEventSink) async throws
    func stop() async
    func prepareSpawn(project: Project) -> SpawnEnvironment
    func didSpawnSession(_ session: SessionHandle)
    func willTerminateSession(_ session: SessionHandle)
}

extension AgentAdapter {
    var continuationArgs: [String] { [] }
    var acceptsPastedImagePaths: Bool { false }
    var transcriptRefinement: AgentTranscriptRefinement? { nil }
}

struct AgentTranscriptRefinement {
    let name: String
    let description: String
    let refiner: any TranscriptRefiner
}
