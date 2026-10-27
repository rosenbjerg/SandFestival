import Foundation

nonisolated struct ClaudeTranscriptRefiner: TranscriptRefiner {
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

    static func environment(inherited: [String: String], shellPath: String?) -> [String: String] {
        var environment = inherited
        if let shellPath {
            environment["PATH"] = shellPath
        }
        // Otherwise the user's CLAUDE.md rides along and steers the rewrite.
        environment["CLAUDE_CODE_DISABLE_CLAUDE_MDS"] = "1"
        return environment
    }

    func refine(_ transcript: String, vocabulary: [String]) async throws -> String {
        let run = OneShotClaudeRun(
            prompt: TranscriptRefinement.prompt(transcript: transcript, vocabulary: vocabulary)
        )
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

    private let prompt: String
    private let lock = NSLock()
    private var state = State.idle

    init(prompt: String) {
        self.prompt = prompt
    }

    func execute() throws -> String {
        let shellPath = UserShellPath.current(blockingUpTo: 1.0)
        guard let nono = CommandResolver.resolve(
            ClaudeTranscriptRefiner.command,
            searchPath: ClaudeCodeUpdater.searchPath(shellPath: shellPath)
        ) else { throw TranscriptRefinerError.unavailable }

        let workingDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("sandfestival-refine-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workingDirectory) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: nono)
        process.arguments = ClaudeTranscriptRefiner.arguments(
            systemPrompt: TranscriptRefinement.instructions,
            prompt: prompt
        )
        process.environment = ClaudeTranscriptRefiner.environment(
            inherited: ProcessInfo.processInfo.environment,
            shellPath: shellPath
        )
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
