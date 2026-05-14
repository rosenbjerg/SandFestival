import Foundation

/// Drives the state machine with a canned event sequence — used by previews
/// and tests, never wired in production.
@MainActor
final class MockAdapter: AgentAdapter {
    static let id = "mock"
    static let displayName = "Mock Agent"

    let defaultCommand: String
    let defaultArgs: [String]

    private weak var sink: AgentEventSink?
    private var liveSessions: [SessionHandle: Task<Void, Never>] = [:]
    private let script: [ScriptStep]

    init(
        command: String = "/bin/sh",
        args: [String] = ["-c", "echo mock; while true; do sleep 1; done"],
        script: [ScriptStep] = MockAdapter.defaultScript
    ) {
        self.defaultCommand = command
        self.defaultArgs = args
        self.script = script
    }

    func start(eventSink: AgentEventSink) async throws {
        self.sink = eventSink
    }

    func stop() async {
        for task in liveSessions.values {
            task.cancel()
        }
        liveSessions.removeAll()
    }

    func prepareSpawn(project: Project) -> SpawnEnvironment { .empty }

    func didSpawnSession(_ session: SessionHandle) {
        liveSessions[session]?.cancel()
        liveSessions[session] = Task { @MainActor [weak self] in
            await self?.runScript(for: session)
        }
    }

    func willTerminateSession(_ session: SessionHandle) {
        liveSessions[session]?.cancel()
        liveSessions.removeValue(forKey: session)
    }

    private func runScript(for session: SessionHandle) async {
        guard let sink else { return }
        for step in script {
            try? await Task.sleep(for: step.delay)
            if Task.isCancelled { return }
            sink.report(projectID: session.projectID, event: step.event)
        }
    }

    struct ScriptStep {
        let delay: Duration
        let event: AgentEvent
    }

    static let defaultScript: [ScriptStep] = [
        ScriptStep(delay: .milliseconds(200), event: .started),
        ScriptStep(delay: .milliseconds(400), event: .working),
        ScriptStep(delay: .seconds(3), event: .waitingForPermission),
        ScriptStep(delay: .seconds(5), event: .working),
        ScriptStep(delay: .seconds(2), event: .idle),
    ]
}
