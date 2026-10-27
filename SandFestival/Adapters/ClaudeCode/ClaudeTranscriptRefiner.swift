import Foundation

nonisolated struct ClaudeTranscriptRefiner: TranscriptRefiner {
    let launcher: AgentLauncher

    var timeout: Duration { .seconds(10) }

    static let command = Project.defaultCommand

    static func arguments(systemPrompt: String, prompt: String) -> [String] {
        ArgsSplitter.split(Project.defaultArgs).wrapper + ["--silent", "--", "claude"] + [
            "-p",
            "--model", "haiku",
            "--tools", "",
            "--strict-mcp-config",
            "--no-session-persistence",
            "--disable-slash-commands",
            "--settings", #"{"disableAllHooks":true}"#,
            "--system-prompt", systemPrompt,
            prompt,
        ]
    }

    // Otherwise the user's CLAUDE.md rides along and steers the rewrite.
    static let environment = ["CLAUDE_CODE_DISABLE_CLAUDE_MDS": "1"]

    func refine(_ transcript: String, vocabulary: [String]) async throws -> String {
        let launch = try await launcher(
            Self.command,
            Self.arguments(
                systemPrompt: TranscriptRefinement.instructions,
                prompt: TranscriptRefinement.prompt(transcript: transcript, vocabulary: vocabulary)
            ),
            Self.environment
        )
        let run = OneShotClaudeRun(launch: launch)
        return try await withTaskCancellationHandler {
            try await Task.detached(priority: .userInitiated) { try run.execute() }.value
        } onCancel: {
            run.cancel()
        }
    }
}

private nonisolated final class OneShotClaudeRun: @unchecked Sendable {
    private enum State {
        case idle
        case running(Process)
        case finished
        case cancelled
    }

    private let launch: AgentLaunch
    private let lock = NSLock()
    private var state = State.idle

    init(launch: AgentLaunch) {
        self.launch = launch
    }

    func execute() throws -> String {
        let workingDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("sandfestival-refine-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workingDirectory) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: launch.executable)
        process.arguments = launch.arguments
        process.environment = launch.environmentDictionary
        process.currentDirectoryURL = workingDirectory
        let stdout = Pipe()
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice

        try start(process)
        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard finish() else { throw CancellationError() }
        guard process.terminationStatus == 0 else { throw TranscriptRefinerError.failed }
        return String(data: output, encoding: .utf8) ?? ""
    }

    func cancel() {
        lock.lock()
        defer { lock.unlock() }
        switch state {
        case .idle:
            state = .cancelled
        case .running(let process):
            process.terminate()
            state = .cancelled
        case .finished, .cancelled:
            break
        }
    }

    private func start(_ process: Process) throws {
        lock.lock()
        defer { lock.unlock() }
        guard case .idle = state else { throw CancellationError() }
        try process.run()
        state = .running(process)
    }

    private func finish() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard case .running = state else { return false }
        state = .finished
        return true
    }
}
