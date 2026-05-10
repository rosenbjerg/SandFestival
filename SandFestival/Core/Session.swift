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

    @ObservationIgnored let terminalView: LocalProcessTerminalView
    @ObservationIgnored private let processBridge: ProcessBridge

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
            state = .errored(reason: String(localized: "session.error.command_not_found"))
            lastError = String(localized: "session.error.command_not_found")
            bumpActivity()
            return
        }
        lastError = nil
        state = .starting
        bumpActivity()
        terminalView.startProcess(
            executable: executable,
            args: project.args,
            environment: composedEnvironment(),
            execName: nil,
            currentDirectory: project.path.path
        )
        state = .idle
        bumpActivity()
    }

    func stop() {
        guard state.isRunning else { return }
        terminalView.terminate()
    }

    func restart() {
        if state.isRunning {
            terminalView.terminate()
            // process termination triggers handleProcessTerminated, which just
            // marks .stopped. The user's restart action sets a flag so the
            // next termination handler re-spawns.
            wantsRestart = true
        } else {
            start()
        }
    }

    @ObservationIgnored private var wantsRestart = false

    func update(project: Project) {
        self.project = project
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

    private func composedEnvironment() -> [String] {
        var entries = Terminal.getEnvironmentVariables()
        var pathOverride = CommandResolver.defaultPathString
        for (key, value) in project.env {
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
