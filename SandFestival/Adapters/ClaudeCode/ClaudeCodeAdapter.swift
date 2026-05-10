import Foundation
import Observation

@MainActor
@Observable
final class ClaudeCodeAdapter: AgentAdapter {
    static let id = "claude-code"
    static let displayName = "Claude Code"

    let defaultCommand = Project.defaultCommand
    let defaultArgs = Project.defaultArgs

    /// `true` once the listener is bound and we've confirmed hooks aren't
    /// installed yet. The UI watches this to show the first-run sheet.
    private(set) var needsInstallation = false

    /// Populated when hook install/uninstall fails — UI can surface it.
    private(set) var lastInstallError: String?

    /// Populated when adapter startup itself fails (listener bind, keychain).
    private(set) var startupError: String?

    @ObservationIgnored private let tokenStore: KeychainTokenStore
    @ObservationIgnored private let portStore: PortStore
    @ObservationIgnored private let settingsManager: SettingsJSONManager
    @ObservationIgnored private var token: String?
    @ObservationIgnored private var port: UInt16?
    @ObservationIgnored private var listener: HookListener?

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
        do {
            let token = try tokenStore.loadOrCreate()
            self.token = token

            let preferredPort = portStore.load() ?? 51789
            let listener = HookListener(token: token) { _ in
                // Body translation lands in Task 8.
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
        guard let token else { return .empty }
        return SpawnEnvironment(additions: ["SAND_FESTIVAL_TOKEN": token])
    }

    func didSpawnSession(_ session: SessionHandle) {
        // session_id binding lands in Task 8.
    }

    func willTerminateSession(_ session: SessionHandle) {
        // session_id cleanup lands in Task 8.
    }

    // MARK: - Hook installation API (used by the first-run sheet)

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

    // MARK: - Internal

    private func refreshNeedsInstallation() {
        guard let port else {
            needsInstallation = false
            return
        }
        do {
            needsInstallation = try !settingsManager.isInstalled(port: port)
        } catch {
            // Malformed settings.json: don't try to merge — surface the error
            // and leave hooks alone so we don't damage user state.
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
