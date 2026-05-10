import Foundation
import Observation

@MainActor
@Observable
final class ClaudeCodeAdapter: AgentAdapter {
    static let id = "claude-code"
    static let displayName = "Claude Code"

    let defaultCommand = Project.defaultCommand
    let defaultArgs = Project.defaultArgs

    private(set) var needsInstallation = false
    private(set) var lastInstallError: String?
    private(set) var startupError: String?

    func clearLastInstallError() { lastInstallError = nil }
    func clearStartupError() { startupError = nil }

    @ObservationIgnored private let tokenStore: KeychainTokenStore
    @ObservationIgnored private let portStore: PortStore
    @ObservationIgnored private let settingsManager: SettingsJSONManager
    @ObservationIgnored private let bindings = SessionBindingStore()
    @ObservationIgnored private var token: String?
    @ObservationIgnored private var port: UInt16?
    @ObservationIgnored private var listener: HookListener?
    @ObservationIgnored private weak var eventSink: AgentEventSink?

    init(
        tokenStore: KeychainTokenStore = KeychainTokenStore(),
        portStore: PortStore = PortStore(),
        settingsManager: SettingsJSONManager = SettingsJSONManager()
    ) {
        self.tokenStore = tokenStore
        self.portStore = portStore
        self.settingsManager = settingsManager
    }

    // MARK: - AgentAdapter

    func start(eventSink: AgentEventSink) async throws {
        self.eventSink = eventSink
        do {
            let token = try tokenStore.loadOrCreate()
            self.token = token

            let preferredPort = portStore.load() ?? 51789
            let listener = HookListener(token: token) { [weak self] body in
                guard let self else { return }
                Task { @MainActor in
                    self.handleHookBody(body)
                }
            }
            let boundPort = try await listener.start(preferredPort: preferredPort)
            self.listener = listener
            self.port = boundPort
            try? portStore.save(boundPort)

            refreshNeedsInstallation()
        } catch {
            startupError = error.localizedDescription
            throw error
        }
    }

    func stop() async {
        listener?.stop()
        listener = nil
    }

    func prepareSpawn(project: Project) -> SpawnEnvironment {
        bindings.registerPendingSpawn(projectID: project.id, cwd: project.path)
        guard let token else { return .empty }
        return SpawnEnvironment(additions: ["SAND_FESTIVAL_TOKEN": token])
    }

    func didSpawnSession(_ session: SessionHandle) {
        // The pending-spawn binding was already registered in prepareSpawn.
        // Nothing further to do here until the first SessionStart hook arrives.
    }

    func willTerminateSession(_ session: SessionHandle) {
        bindings.unbindAll(projectID: session.projectID)
    }

    // MARK: - Hook installation (used by the first-run sheet)

    func installHooks() {
        guard let port else { return }
        do {
            try settingsManager.install(port: port)
            lastInstallError = nil
            needsInstallation = false
        } catch {
            lastInstallError = describe(error)
        }
    }

    func uninstallHooks() {
        do {
            try settingsManager.uninstall()
            lastInstallError = nil
            refreshNeedsInstallation()
        } catch {
            lastInstallError = describe(error)
        }
    }

    func previewInstallation() -> SettingsDiffPreview? {
        guard let port else { return nil }
        do {
            return try settingsManager.previewInstall(port: port)
        } catch {
            lastInstallError = describe(error)
            return nil
        }
    }

    // MARK: - Hook body handling

    private func handleHookBody(_ body: Data) {
        guard let payload = HookPayloadDecoder.decode(body) else { return }

        let projectID: UUID?
        if payload.hookEventName == HookEvent.sessionStart.rawValue {
            projectID = bindings.bindOnSessionStart(sessionID: payload.sessionID, cwd: payload.cwd)
            ?? bindings.projectID(forSession: payload.sessionID)
        } else {
            projectID = bindings.projectID(forSession: payload.sessionID)
        }

        guard let projectID, let event = HookPayloadTranslator.translate(payload) else { return }
        eventSink?.report(matching: .projectID(projectID), event: event)

        if payload.hookEventName == HookEvent.sessionEnd.rawValue {
            bindings.unbind(sessionID: payload.sessionID)
        }
    }

    // MARK: - Internal

    private func refreshNeedsInstallation() {
        guard let port else {
            needsInstallation = false
            return
        }
        do {
            needsInstallation = try !settingsManager.isInstalled(port: port)
        } catch {
            needsInstallation = false
            lastInstallError = describe(error)
        }
    }

    private func describe(_ error: any Error) -> String {
        if let settingsError = error as? SettingsJSONManagerError {
            switch settingsError {
            case .malformedJSON:
                return String(localized: "claudecode.error.settings_malformed")
            case .writeFailed(let reason):
                return String(localized: "claudecode.error.settings_write_failed") + " (\(reason))"
            }
        }
        return error.localizedDescription
    }
}
