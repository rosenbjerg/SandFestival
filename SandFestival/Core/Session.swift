import AppKit
import Observation
import SwiftTerm

@MainActor
@Observable
final class Session: Identifiable {
    var project: Project
    private(set) var state: SessionState = .stopped
    private(set) var lastActivityAt: Date = Date()
    private(set) var lastError: String?
    private(set) var metadata: AgentMetadata = .empty

    @ObservationIgnored let terminalView: LocalProcessTerminalView
    @ObservationIgnored private let processBridge: ProcessBridge
    @ObservationIgnored private var lastSameStateBumpAt: Date?

    /// Returns env additions to merge into the spawn env. Wired by
    /// SessionManager so every start() — toolbar, overlay, auto-restart —
    /// picks up the current adapter's prepareSpawn output.
    @ObservationIgnored var spawnEnvProvider: ((Project) -> [String: String])?

    /// Called after a successful spawn so adapters can register a handle.
    @ObservationIgnored var onDidSpawn: ((Project) -> Void)?

    /// Sub-second debounce for same-state activity bumps (e.g. heartbeat
    /// floods while in working state) so the sidebar doesn't re-render
    /// dozens of times per second.
    @ObservationIgnored private let sameStateBumpInterval: TimeInterval = 0.5

    var id: Project.ID { project.id }

    init(project: Project) {
        self.project = project
        let view = LocalProcessTerminalView(frame: .zero)
        self.terminalView = view
        let bridge = ProcessBridge()
        self.processBridge = bridge
        view.processDelegate = bridge
        bridge.onProcessTerminated = { [weak self] exitCode in
            Task { @MainActor in
                self?.handleProcessTerminated(exitCode: exitCode)
            }
        }
    }

    // MARK: - Lifecycle

    func start() {
        guard !state.isRunning else { return }
        guard let executable = CommandResolver.resolve(project.command) else {
            let reason = String(localized: "session.error.command_not_found")
            state = .errored(reason: reason)
            lastError = reason
            bumpActivity()
            return
        }
        let extraEnvironment = spawnEnvProvider?(project) ?? [:]
        lastError = nil
        state = .starting
        bumpActivity()
        terminalView.startProcess(
            executable: executable,
            args: project.args,
            environment: composedEnvironment(extra: extraEnvironment),
            execName: nil,
            currentDirectory: project.path.path
        )
        // Fallback transition to .idle so the UI shows life even when no
        // adapter is feeding events. When the real adapter delivers .started,
        // the state machine treats it as a no-op.
        state = .idle
        bumpActivity()
        onDidSpawn?(project)
    }

    func stop() {
        guard state.isRunning else { return }
        terminalView.terminate()
    }

    func restart() {
        if state.isRunning {
            terminalView.terminate()
            wantsRestart = true
        } else {
            start()
        }
    }

    @ObservationIgnored private var wantsRestart = false

    func update(project: Project) {
        self.project = project
    }

    // MARK: - Agent event ingestion

    func apply(event: AgentEvent) {
        let next = SessionStateMachine.next(from: state, event: event)
        if next != state {
            state = next
            lastActivityAt = Date()
            lastSameStateBumpAt = nil
            if case .errored(let reason) = next {
                lastError = reason
            }
        } else {
            // Same-state event (heartbeat / repeat). Debounce activity bumps.
            let now = Date()
            if let last = lastSameStateBumpAt, now.timeIntervalSince(last) < sameStateBumpInterval {
                return
            }
            lastSameStateBumpAt = now
            lastActivityAt = now
        }
    }

    func updateMetadata(_ newMetadata: AgentMetadata) {
        metadata = newMetadata
    }

    private func handleProcessTerminated(exitCode: Int32?) {
        state = .stopped
        bumpActivity()
        if wantsRestart {
            wantsRestart = false
            start()
        }
    }

    // MARK: - Helpers

    private func bumpActivity() {
        lastActivityAt = Date()
    }

    private func composedEnvironment(extra: [String: String]) -> [String] {
        var entries = Terminal.getEnvironmentVariables()
        var pathOverride = CommandResolver.defaultPathString
        var merged = project.env
        for (key, value) in extra {
            merged[key] = value
        }
        for (key, value) in merged {
            if key == "PATH" {
                pathOverride = value
            } else {
                entries.append("\(key)=\(value)")
            }
        }
        entries.append("PATH=\(pathOverride)")
        return entries
    }
}

// MARK: - Process delegate bridge

private final class ProcessBridge: NSObject, LocalProcessTerminalViewDelegate {
    var onProcessTerminated: ((Int32?) -> Void)?

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        onProcessTerminated?(exitCode)
    }
}
