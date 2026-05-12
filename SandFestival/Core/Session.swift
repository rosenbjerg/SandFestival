import AppKit
import Foundation
import Observation
import SwiftTerm

@MainActor
@Observable
final class Session: Identifiable {
    var project: Project
    private(set) var state: SessionState = .stopped
    /// True between the first soft-stop (`stop()` / `restart()`) and the
    /// process actually exiting. The toolbar reads this to flip the Stop
    /// button to "Force Stop" so a second click escalates to SIGKILL.
    private(set) var softStopRequested: Bool = false
    /// Wall-clock instant the session entered its current state. The sidebar
    /// uses this to display "waiting Xm" while in attention states; it is
    /// **not** bumped by heartbeats or other same-state events, so the count
    /// reflects "how long has Claude been waiting on you" rather than "when
    /// did the last hook fire".
    private(set) var enteredCurrentStateAt: Date = Date()
    private(set) var lastError: String?
    /// Latest terminal title emitted by the child process (claude sets this
    /// via the OSC 0/2 escape sequence to summarise the current task). Cleared
    /// on start/stop so a stale title never outlives the process.
    private(set) var terminalTitle: String?

    @ObservationIgnored let terminalView: SessionTerminalView
    @ObservationIgnored private let processBridge: ProcessBridge

    /// Returns env additions to merge into the spawn env. Wired by
    /// SessionManager so every start() — toolbar, overlay, auto-restart —
    /// picks up the current adapter's prepareSpawn output.
    @ObservationIgnored var spawnEnvProvider: ((Project) -> [String: String])?

    /// Called after a successful spawn so adapters can register a handle.
    @ObservationIgnored var onDidSpawn: ((Project) -> Void)?

    /// Called after the OS-level process exits — including unexpected exits
    /// the user didn't trigger. Adapters use this to drop any per-process
    /// state (Claude Code clears its live cwd→project binding here so a
    /// later hand-launched `claude` from the same cwd doesn't attach to the
    /// dead session). User-initiated stop/restart paths also fire this once
    /// the kill takes effect — duplicate cleanup is harmless.
    @ObservationIgnored var onDidTerminate: ((Project) -> Void)?

    /// Fires when the session moves from one state to another. Same-state
    /// "transitions" don't fire — heartbeats stay quiet. Wired by SessionManager
    /// so cross-session coordinators (attention notifier, etc.) can react
    /// without each owning a separate observation tracker.
    @ObservationIgnored var onStateChanged: ((SessionState, SessionState) -> Void)?

    var id: Project.ID { project.id }

    init(project: Project) {
        self.project = project
        let view = SessionTerminalView(frame: .zero)
        self.terminalView = view
        let bridge = ProcessBridge()
        self.processBridge = bridge
        view.processDelegate = bridge
        bridge.onProcessTerminated = { [weak self] exitCode in
            Task { @MainActor in
                self?.handleProcessTerminated(exitCode: exitCode)
            }
        }
        bridge.onTerminalTitleChanged = { [weak self] title in
            Task { @MainActor in
                self?.updateTerminalTitle(title)
            }
        }
        view.onUserSent = { [weak self] in
            self?.handleUserKeystroke()
        }
    }

    // MARK: - Lifecycle

    func start() {
        guard !state.isRunning else { return }
        guard let executable = CommandResolver.resolve(project.command) else {
            let reason = String(localized: "session.error.command_not_found")
            transition(to: .errored(reason: reason))
            lastError = reason
            return
        }
        let extraEnvironment = spawnEnvProvider?(project) ?? [:]
        lastError = nil
        terminalTitle = nil
        wantsStop = false
        softStopRequested = false
        transition(to: .starting)
        terminalView.startProcess(
            executable: executable,
            args: project.args,
            environment: composedEnvironment(extra: extraEnvironment),
            execName: nil,
            currentDirectory: project.path.path
        )
        processStartedAt = Date()
        // Fallback transition to .idle so the UI shows life even when no
        // adapter is feeding events. When the real adapter delivers .started,
        // the state machine treats it as a no-op.
        transition(to: .idle)
        onDidSpawn?(project)
    }

    /// Soft stop: SIGINT the wrapper PID so nono can run its post-kill prompt
    /// on the still-attached PTY. SwiftTerm's `terminate()` would close the
    /// PTY, flip `running` to false (silently dropping further keystrokes),
    /// and cancel the child monitor — none of which we want while nono is
    /// asking the user to confirm something. The natural exit path
    /// (`childMonitor` → `handleProcessTerminated`) flips us to `.stopped`
    /// once nono actually exits.
    func stop() {
        guard state.isRunning else { return }
        let pid = terminalView.process.shellPid
        guard pid != 0 else { return }
        wantsStop = true
        softStopRequested = true
        kill(pid, SIGINT)
    }

    func restart() {
        if state.isRunning {
            let pid = terminalView.process.shellPid
            guard pid != 0 else { return }
            wantsStop = true
            wantsRestart = true
            softStopRequested = true
            kill(pid, SIGINT)
        } else {
            start()
        }
    }

    /// Hard stop: SIGKILL the wrapper PID. Unblocks the "nono is wedged on
    /// its prompt and won't quit" case after a soft stop. nono can't trap
    /// SIGKILL, so the OS-level process death is guaranteed and the
    /// existing `childMonitor` → `handleProcessTerminated` path runs
    /// normally — we don't have to yank the PTY ourselves. Cancels any
    /// queued restart so "Force Stop" really means stop, not restart.
    func forceStop() {
        guard state.isRunning else { return }
        let pid = terminalView.process.shellPid
        guard pid != 0 else { return }
        wantsStop = true
        wantsRestart = false
        kill(pid, SIGKILL)
    }

    @ObservationIgnored private var wantsRestart = false
    @ObservationIgnored private var wantsStop = false
    @ObservationIgnored private var processStartedAt: Date?

    func update(project: Project) {
        self.project = project
    }

    // MARK: - Agent event ingestion

    func apply(event: AgentEvent) {
        let next = SessionStateMachine.next(from: state, event: event)
        guard next != state else { return }  // Heartbeats and other same-state events are intentional no-ops here.
        transition(to: next)
        if case .errored(let reason) = next {
            lastError = reason
        }
    }

    /// Called when the user types into this session's terminal. Used as a
    /// fallback for `waitingForIdle` because Claude Code doesn't fire any
    /// hook when the user dismisses an interactive prompt (e.g. cancelling
    /// `AskUserQuestion` with Ctrl+C). Other waiting states have their own
    /// resolution paths and aren't affected.
    func handleUserKeystroke() {
        guard state == .waitingForIdle else { return }
        transition(to: .idle)
    }

    private func handleProcessTerminated(exitCode: Int32?) {
        terminalTitle = nil
        let userInitiated = wantsStop
        let runDuration = processStartedAt.map { Date().timeIntervalSince($0) } ?? .infinity
        wantsStop = false
        softStopRequested = false
        processStartedAt = nil

        // Surface unexpected exits (non-zero status, or any exit within the
        // startup window) so the user can see why nono/claude died instead of
        // just watching the terminal flash. User-initiated stop/restart paths
        // bypass this because the SIGTERM we sent isn't a failure.
        if !userInitiated, exitCode != 0 || runDuration < Session.startupFailureWindow {
            lastError = formatExitFailure(exitCode: exitCode)
        }

        // Notify before `.stopped` so adapters drop per-process state before
        // any restart re-registers fresh bindings for the same cwd.
        onDidTerminate?(project)
        transition(to: .stopped)
        if wantsRestart {
            wantsRestart = false
            start()
        }
    }

    private static let startupFailureWindow: TimeInterval = 3

    private func formatExitFailure(exitCode: Int32?) -> String {
        let header: String
        if let code = exitCode {
            header = String(format: String(localized: "session.error.exited_with_code"), code)
        } else {
            header = String(localized: "session.error.exited_unexpectedly")
        }
        let tail = recentTerminalOutput()
        return tail.isEmpty ? header : "\(header)\n\n\(tail)"
    }

    private func recentTerminalOutput(maxLines: Int = 8) -> String {
        guard let terminal = terminalView.terminal else { return "" }
        let data = terminal.getBufferAsData()
        guard let text = String(data: data, encoding: .utf8) else { return "" }
        let lines = text
            .split(omittingEmptySubsequences: false, whereSeparator: { $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return lines.suffix(maxLines).joined(separator: "\n")
    }

    private func updateTerminalTitle(_ title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        terminalTitle = trimmed.isEmpty ? nil : trimmed
    }

    // MARK: - Helpers

    private func transition(to next: SessionState) {
        guard next != state else { return }
        let previous = state
        state = next
        enteredCurrentStateAt = Date()
        onStateChanged?(previous, next)
    }

    private func composedEnvironment(extra: [String: String]) -> [String] {
        Session.composeEnvironment(
            inherited: Terminal.getEnvironmentVariables(),
            projectEnv: project.env,
            extra: extra
        )
    }

    /// PATH precedence is: explicit project/adapter override → inherited from
    /// the parent process (the user's shell PATH) → `CommandResolver`'s
    /// hardcoded fallback. Older behavior replaced every inherited PATH with
    /// the fallback unconditionally, which silently broke setups that put
    /// `claude` / `nono` in non-system locations (mise, asdf, ~/.cargo/bin,
    /// etc.). Extracted as a pure static so the precedence rules can be
    /// tested without spinning up a Session.
    static func composeEnvironment(
        inherited: [String],
        projectEnv: [String: String],
        extra: [String: String]
    ) -> [String] {
        var merged = projectEnv
        for (key, value) in extra {
            merged[key] = value
        }
        let explicitPath = merged.removeValue(forKey: "PATH")

        var entries = inherited.filter { !$0.hasPrefix("PATH=") }
        for (key, value) in merged {
            entries.append("\(key)=\(value)")
        }

        let resolvedPath = explicitPath
            ?? Session.extractPATH(from: inherited)
            ?? CommandResolver.defaultPathString
        entries.append("PATH=\(resolvedPath)")
        return entries
    }

    private static func extractPATH(from entries: [String]) -> String? {
        for entry in entries where entry.hasPrefix("PATH=") {
            let value = String(entry.dropFirst("PATH=".count))
            return value.isEmpty ? nil : value
        }
        return nil
    }
}

// MARK: - Process delegate bridge

private final class ProcessBridge: NSObject, LocalProcessTerminalViewDelegate {
    var onProcessTerminated: ((Int32?) -> Void)?
    var onTerminalTitleChanged: ((String) -> Void)?

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        onTerminalTitleChanged?(title)
    }
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        onProcessTerminated?(exitCode)
    }
}
