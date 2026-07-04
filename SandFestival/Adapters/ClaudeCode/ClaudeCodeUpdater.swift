import Foundation

/// Runs `claude update` to self-update the Claude Code install, then reports
/// the captured output and whether it succeeded. Non-interactive and safe to
/// call off the main actor (it blocks on `waitUntilExit()`).
///
/// `claude update` self-updates the native installer's binary; Homebrew/npm
/// installs aren't updated by it and instead print their own guidance, which
/// we surface verbatim so the user learns what to run.
enum ClaudeCodeUpdater {
    struct UpdateResult: Equatable {
        /// The process ran and exited 0. False also covers "claude not found"
        /// and launch failures — `output` explains which.
        let succeeded: Bool
        /// Combined stdout+stderr (or the failure reason when the process
        /// never ran). Shown to the user in the update sheet.
        let output: String
    }

    /// Runs the update synchronously and returns its outcome. Call from a
    /// detached task — this blocks the calling thread until `claude` exits.
    nonisolated static func runUpdate() -> UpdateResult {
        // Prefer the user's interactive-shell PATH so a `claude` installed
        // under a version manager (nvm/fnm/mise) or `~/.local/bin` resolves
        // the same way it does in Terminal, mirroring how sessions are spawned.
        let shellPath = UserShellPath.current(blockingUpTo: 1.0)
        guard let claude = CommandResolver.resolve("claude", searchPath: searchPath(shellPath: shellPath)) else {
            return UpdateResult(succeeded: false, output: String(localized: "update.error.claude_not_found"))
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: claude)
        task.arguments = ["update"]
        task.standardInput = FileHandle.nullDevice
        // `claude update` may shell out to its installer; hand it the same
        // resolved PATH so those child lookups succeed too.
        if let shellPath {
            var environment = ProcessInfo.processInfo.environment
            environment["PATH"] = shellPath
            task.environment = environment
        }

        // stdout and stderr merge into one pipe — the sheet shows a single
        // transcript and the output is a few lines, well under the pipe buffer.
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
        } catch {
            return UpdateResult(succeeded: false, output: error.localizedDescription)
        }

        // Read to EOF *before* waiting: EOF arrives when the child closes its
        // write ends (i.e. on exit), so this can't deadlock and waitUntilExit
        // then returns immediately.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        let output = (String(data: data, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return UpdateResult(succeeded: task.terminationStatus == 0, output: output)
    }

    /// Search path used to locate `claude`. The resolved interactive-shell
    /// PATH (when available) takes precedence over the hardcoded fallback so
    /// non-standard installs are found; the fallback dirs are appended so a
    /// native `~/.local/bin` install still resolves if shell resolution missed
    /// or hasn't finished. Pure so the precedence is testable without a shell.
    nonisolated static func searchPath(shellPath: String?) -> [String] {
        let shellDirs = shellPath?
            .split(separator: ":", omittingEmptySubsequences: true)
            .map(String.init) ?? []
        guard !shellDirs.isEmpty else { return CommandResolver.defaultSearchPath }
        var seen = Set(shellDirs)
        return shellDirs + CommandResolver.defaultSearchPath.filter { seen.insert($0).inserted }
    }
}
