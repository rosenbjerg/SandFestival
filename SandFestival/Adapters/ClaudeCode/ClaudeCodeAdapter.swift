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

    @ObservationIgnored private let tokenStore: any TokenStore
    @ObservationIgnored private let settingsManager: SettingsJSONManager
    @ObservationIgnored private let bindings = SessionBindingStore()
    @ObservationIgnored private var token: String?
    @ObservationIgnored private var listener: HookListener?
    @ObservationIgnored private weak var eventSink: AgentEventSink?

    /// Fixed port the listener binds to. Surfaced here so the adapter and
    /// settings.json factory share one source of truth. Configurable via
    /// init for test isolation; production always uses the default.
    @ObservationIgnored private let port: UInt16

    init(
        port: UInt16 = HookListener.defaultPort,
        tokenStore: any TokenStore = KeychainTokenStore(),
        settingsManager: SettingsJSONManager = SettingsJSONManager()
    ) {
        self.port = port
        self.tokenStore = tokenStore
        self.settingsManager = settingsManager
    }

    // MARK: - AgentAdapter

    func start(eventSink: AgentEventSink) async throws {
        self.eventSink = eventSink
        do {
            let token = try tokenStore.loadOrCreate()
            self.token = token

            let listener = HookListener(port: port, token: token) { [weak self] body in
                guard let self else { return }
                Task { @MainActor in
                    self.handleHookBody(body)
                }
            }
            try await listener.start()
            self.listener = listener

            refreshNeedsInstallation()
        } catch {
            startupError = describe(error)
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

    func didSpawnSession(_ session: SessionHandle) {}

    func willTerminateSession(_ session: SessionHandle) {
        bindings.unbindAll(projectID: session.projectID)
    }

    // MARK: - Hook installation (used by the first-run sheet)

    func installHooks() {
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

        guard let projectID else { return }

        // Surface permission_mode on every payload that carries it — Claude
        // includes it on most hook events, so the sidebar badge tracks the
        // live mode without needing to special-case which events update it.
        if let mode = payload.permissionMode, !mode.isEmpty {
            eventSink?.updateMetadata(
                matching: .projectID(projectID),
                metadata: AgentMetadata(permissionMode: mode)
            )
        }

        if let event = HookPayloadTranslator.translate(payload) {
            eventSink?.report(matching: .projectID(projectID), event: event)
        }

        if payload.hookEventName == HookEvent.sessionEnd.rawValue {
            bindings.unbind(sessionID: payload.sessionID)
        }
    }

    // MARK: - Internal

    private func refreshNeedsInstallation() {
        do {
            switch try settingsManager.detectInstallState(port: port) {
            case .current:
                needsInstallation = false
            case .outdated:
                try settingsManager.install(port: port)
                needsInstallation = false
            case .notInstalled:
                needsInstallation = true
            }
        } catch {
            needsInstallation = false
            lastInstallError = describe(error)
        }
    }

    private func describe(_ error: any Error) -> String {
        if let listenerError = error as? HookListenerError {
            switch listenerError {
            case .bindFailed(let port):
                return String(
                    format: String(localized: "claudecode.error.port_in_use"),
                    String(port)
                )
            case .invalidPort:
                return String(localized: "claudecode.error.port_invalid")
            }
        }
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
