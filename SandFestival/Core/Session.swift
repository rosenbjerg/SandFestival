import AppKit
import Foundation
import Observation
import SwiftTerm

@MainActor
@Observable
final class Session: Identifiable {
    var project: Project
    private(set) var state: SessionState = .stopped
    private(set) var softStopRequested: Bool = false
    private(set) var enteredCurrentStateAt: Date = Date()
    private(set) var lastError: String?
    private(set) var terminalTitle: String?
    private(set) var hasUnseenOutput = false
    private(set) var hasOutputBelowViewport = false

    @ObservationIgnored let terminalView: SessionTerminalView
    @ObservationIgnored private let processBridge: ProcessBridge

    @ObservationIgnored var spawnEnvProvider: ((Project) -> [String: String])?
    @ObservationIgnored var continuationArgsProvider: (() -> [String])?
    @ObservationIgnored private var extraAgentArgs: [String] = []

    var canContinue: Bool {
        !(continuationArgsProvider?() ?? []).isEmpty
    }

    @ObservationIgnored var onDidSpawn: ((Project) -> Void)?
    @ObservationIgnored var onDidTerminate: ((Project) -> Void)?
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
        view.onOutputBelowViewportChanged = { [weak self] value in
            self?.hasOutputBelowViewport = value
        }
    }

    func scrollToBottom() {
        terminalView.scroll(toPosition: 1)
    }

    // MARK: - Lifecycle

    func start() {
        launch(extraAgentArgs: [])
    }

    func startContinuing() {
        launch(extraAgentArgs: continuationArgsProvider?() ?? [])
    }

    private func launch(extraAgentArgs: [String]) {
        guard !state.isRunning else { return }
        guard let executable = CommandResolver.resolve(project.command) else {
            let reason = String(localized: "session.error.command_not_found")
            transition(to: .errored(reason: reason))
            lastError = reason
            return
        }
        self.extraAgentArgs = extraAgentArgs
        let extraEnvironment = spawnEnvProvider?(project) ?? [:]
        lastError = nil
        terminalTitle = nil
        wantsStop = false
        softStopRequested = false
        transition(to: .starting)
        terminalView.startProcess(
            executable: executable,
            args: Session.composeArgs(base: project.args, extraAgentArgs: extraAgentArgs),
            environment: composedEnvironment(extra: extraEnvironment),
            execName: nil,
            currentDirectory: project.path.path
        )
        processStartedAt = Date()
        // Without this a session whose adapter never reports sits in .starting forever.
        transition(to: .idle)
        onDidSpawn?(project)
    }

    static func composeArgs(base: [String], extraAgentArgs: [String]) -> [String] {
        guard !extraAgentArgs.isEmpty else { return base }
        if base.contains("--") {
            let split = ArgsSplitter.split(base)
            return ArgsSplitter.join(wrapper: split.wrapper, agent: split.agent + extraAgentArgs)
        }
        return base + extraAgentArgs
    }

    // SIGINT, not SwiftTerm's terminate(): terminate() closes the PTY, which kills
    // nono's post-stop prompt and silently drops the keystrokes answering it.
    func stop() {
        guard state.isRunning else { return }
        let pid = terminalView.process.shellPid
        guard pid != 0 else { return }
        wantsStop = true
        // A stop after a queued restart() must actually stop.
        wantsRestart = false
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

    func restartContinuing() {
        let continuation = continuationArgsProvider?() ?? []
        if state.isRunning {
            let pid = terminalView.process.shellPid
            guard pid != 0 else { return }
            extraAgentArgs = continuation
            wantsStop = true
            wantsRestart = true
            softStopRequested = true
            kill(pid, SIGINT)
        } else {
            startContinuing()
        }
    }

    // The whole group, not the wrapper pid: nono outlives its child on purpose,
    // and killing only the wrapper orphans the agent instead of ending it.
    func forceStop() {
        guard state.isRunning else { return }
        let pid = terminalView.process.shellPid
        guard pid != 0 else { return }
        wantsStop = true
        wantsRestart = false
        ProcessGroupTerminator.signalGroup(leader: pid, signal: SIGKILL)
    }

    @discardableResult
    func forceStopAndWait(timeout: Duration = .seconds(5)) async -> Bool {
        let pid = terminalView.process.shellPid
        // Guard on the process, not `state`: once the exit was observed the pid
        // may be recycled, and signalling a recycled pid is worse than nothing.
        guard terminalView.process.running, pid != 0 else { return true }
        wantsStop = true
        wantsRestart = false
        softStopRequested = false
        // Snapshot before signalling: a setsid'd descendant is reachable only
        // through its parent chain, which breaks the moment the parent dies.
        let tracked = ProcessGroupTerminator.descendants(of: pid)
        ProcessGroupTerminator.signalAll(leader: pid, tracked: tracked, signal: SIGKILL)

        let clear = await waitForGroupToClear(leader: pid, tracked: tracked, timeout: timeout)
        // Let SwiftTerm's exit monitor run waitpid before the caller drops us,
        // or the child is left a zombie.
        if clear {
            await drainTerminationCallback()
        }
        return clear
    }

    private func waitForGroupToClear(
        leader pid: pid_t,
        tracked: Set<ProcessGroupTerminator.TrackedProcess>,
        timeout: Duration
    ) async -> Bool {
        var tracked = tracked
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while true {
            let survivors = ProcessGroupTerminator.liveMembers(leader: pid, tracked: tracked)
            if survivors.isEmpty { return true }
            guard ContinuousClock.now < deadline else { return false }
            // Re-widen and re-signal each sweep: anything forked since the last
            // snapshot never saw the first SIGKILL.
            tracked.formUnion(ProcessGroupTerminator.descendants(ofAnyOf: Set(survivors)))
            ProcessGroupTerminator.signalAll(leader: pid, tracked: tracked, signal: SIGKILL)
            try? await Task.sleep(for: Session.terminationPollInterval)
        }
    }

    private func drainTerminationCallback() async {
        for _ in 0..<Session.terminationDrainPolls where state.isRunning {
            try? await Task.sleep(for: Session.terminationPollInterval)
        }
    }

    private static let terminationPollInterval: Duration = .milliseconds(25)
    private static let terminationDrainPolls = 8

    @ObservationIgnored private var wantsRestart = false
    @ObservationIgnored private var wantsStop = false
    @ObservationIgnored private var processStartedAt: Date?

    func update(project: Project) {
        self.project = project
    }

    func markOutputUnseen() {
        guard !hasUnseenOutput else { return }
        hasUnseenOutput = true
    }

    func markOutputSeen() {
        guard hasUnseenOutput else { return }
        hasUnseenOutput = false
    }

    // MARK: - Agent event ingestion

    func apply(event: AgentEvent) {
        if case .sessionRestarted = event {
            terminalTitle = nil
        }
        let next = SessionStateMachine.next(from: state, event: event)
        guard next != state else { return }
        transition(to: next)
        if case .errored(let reason) = next {
            lastError = reason
        }
    }

    func handleUserKeystroke() {
        apply(event: .userInteracted)
    }

    private func handleProcessTerminated(exitCode: Int32?) {
        terminalTitle = nil
        let userInitiated = wantsStop
        let runDuration = processStartedAt.map { Date().timeIntervalSince($0) } ?? .infinity
        wantsStop = false
        softStopRequested = false
        processStartedAt = nil

        if !userInitiated, exitCode != 0 || runDuration < Session.startupFailureWindow {
            lastError = formatExitFailure(exitCode: exitCode)
        }

        // Must precede the relaunch: the adapter's unbind would otherwise wipe
        // the fresh spawn's registration.
        onDidTerminate?(project)
        transition(to: .stopped)
        if wantsRestart {
            wantsRestart = false
            launch(extraAgentArgs: extraAgentArgs)
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
        var trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = trimmed.unicodeScalars.first,
           !CharacterSet.alphanumerics.contains(first) {
            let afterSymbol = trimmed.dropFirst()
            if afterSymbol.first?.isWhitespace == true {
                trimmed = afterSymbol.drop { $0.isWhitespace }.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
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
            inherited: Session.inheritedEnvironment(),
            projectEnv: project.env,
            extra: extra
        )
    }

    static func inheritedEnvironment() -> [String] {
        var inherited = Terminal.getEnvironmentVariables()
        // Blocks on the first call: the first session start would otherwise
        // race the background resolution and fall back to launchd's PATH.
        if let shellPath = UserShellPath.current(blockingUpTo: 0.8) {
            inherited.removeAll { $0.hasPrefix("PATH=") }
            inherited.append("PATH=\(shellPath)")
        }
        return inherited
    }

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
