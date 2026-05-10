import Foundation

@MainActor
final class ClaudeCodeAdapter: AgentAdapter {
    static let id = "claude-code"
    static let displayName = "Claude Code"

    let defaultCommand = Project.defaultCommand
    let defaultArgs = Project.defaultArgs

    private let tokenStore: KeychainTokenStore
    private let portStore: PortStore
    private var token: String?
    private var port: UInt16?
    private var listener: HookListener?

    init(tokenStore: KeychainTokenStore = KeychainTokenStore(), portStore: PortStore = PortStore()) {
        self.tokenStore = tokenStore
        self.portStore = portStore
    }

    // MARK: - AgentAdapter

    func start(eventSink: AgentEventSink) async throws {
        let token = try tokenStore.loadOrCreate()
        self.token = token

        let preferredPort = portStore.load() ?? 51789
        let listener = HookListener(token: token) { _ in
            // Body translation lands in Task 8. The listener already
            // authenticates and acks every request.
        }
        let boundPort = try await listener.start(preferredPort: preferredPort)
        self.listener = listener
        self.port = boundPort
        try? portStore.save(boundPort)
    }

    func stop() async {
        listener?.stop()
        listener = nil
    }

    func prepareSpawn(project: Project) -> SpawnEnvironment {
        guard let token else { return .empty }
        return SpawnEnvironment(additions: ["SAND_FESTIVAL_TOKEN": token])
    }

    func didSpawnSession(_ session: SessionHandle) {
        // session_id binding lands in Task 8 alongside hook event translation.
    }

    func willTerminateSession(_ session: SessionHandle) {
        // session_id cleanup lands in Task 8.
    }
}
