import Foundation

enum ClaudeCodeUpdater {
    struct UpdateResult: Equatable {
        let succeeded: Bool
        let output: String
    }

    nonisolated static func runUpdate() -> UpdateResult {
        let shellPath = UserShellPath.current(blockingUpTo: 1.0)
        guard let claude = CommandResolver.resolve("claude", searchPath: searchPath(shellPath: shellPath)) else {
            return UpdateResult(succeeded: false, output: String(localized: "update.error.claude_not_found"))
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: claude)
        task.arguments = ["update"]
        task.standardInput = FileHandle.nullDevice
        // claude update shells out to its installer, which needs the same PATH.
        if let shellPath {
            var environment = ProcessInfo.processInfo.environment
            environment["PATH"] = shellPath
            task.environment = environment
        }

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
        } catch {
            return UpdateResult(succeeded: false, output: error.localizedDescription)
        }

        // Read to EOF before waiting, or a full pipe deadlocks against the child.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        let output = (String(data: data, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return UpdateResult(succeeded: task.terminationStatus == 0, output: output)
    }

    nonisolated static func searchPath(shellPath: String?) -> [String] {
        let shellDirs = shellPath?
            .split(separator: ":", omittingEmptySubsequences: true)
            .map(String.init) ?? []
        guard !shellDirs.isEmpty else { return CommandResolver.defaultSearchPath }
        var seen = Set(shellDirs)
        return shellDirs + CommandResolver.defaultSearchPath.filter { seen.insert($0).inserted }
    }
}
