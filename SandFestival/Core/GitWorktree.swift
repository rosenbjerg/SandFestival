import Foundation

/// Thin wrapper around `git worktree` and `git branch` calls used by the
/// project-duplicate flow. Functions are `nonisolated` so callers on the
/// MainActor can hop to a background `Task` for the blocking
/// `Process.waitUntilExit()`.
enum GitWorktree {
    /// True when `path` looks like a git working tree (regular repo *or*
    /// an existing worktree — both have a `.git` entry, file or dir).
    static func isGitRepo(at path: URL) -> Bool {
        let gitPath = path.appendingPathComponent(".git").path
        return FileManager.default.fileExists(atPath: gitPath)
    }

    /// Local branch names in sidebar order (whatever `git branch` returns).
    /// Empty array on any failure — caller should treat that as "user types
    /// the base branch manually" rather than surfacing an error.
    nonisolated static func listLocalBranches(at path: URL) -> [String] {
        guard let result = runGit(["branch", "--format=%(refname:short)"], at: path),
              result.exitCode == 0
        else { return [] }
        return result.stdout
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Async wrapper that runs the (subprocess-spawning) branch listing
    /// off the main actor. SwiftUI view construction blocks on
    /// `waitUntilExit()` otherwise, jamming the runloop while the system
    /// is trying to present the sheet — same shape as the
    /// `NonoProfileDiscovery.availableProfilesAsync` fix.
    static func listLocalBranchesAsync(at path: URL) async -> [String] {
        await Task.detached(priority: .userInitiated) {
            listLocalBranches(at: path)
        }.value
    }

    /// `git worktree add -b <newBranch> <newPath> [<base>]` from `sourceRepoPath`.
    nonisolated static func addWorktree(
        newBranch: String,
        newPath: URL,
        base: String?,
        sourceRepoPath: URL
    ) -> Result<Void, GitWorktreeError> {
        var args = ["worktree", "add", "-b", newBranch, newPath.path]
        if let base, !base.isEmpty {
            args.append(base)
        }
        return runChecked(args, at: sourceRepoPath)
    }

    /// `git worktree remove [--force] <worktreePath>` from `sourceRepoPath`.
    /// Run from the source repo because the worktree dir may be gone already.
    nonisolated static func removeWorktree(
        worktreePath: URL,
        sourceRepoPath: URL,
        force: Bool
    ) -> Result<Void, GitWorktreeError> {
        var args = ["worktree", "remove"]
        if force { args.append("--force") }
        args.append(worktreePath.path)
        return runChecked(args, at: sourceRepoPath)
    }

    // MARK: - Internals

    nonisolated private static func runChecked(
        _ args: [String],
        at cwd: URL
    ) -> Result<Void, GitWorktreeError> {
        guard let result = runGit(args, at: cwd) else {
            return .failure(.gitNotFound)
        }
        if result.exitCode == 0 { return .success(()) }
        return .failure(.commandFailed(exitCode: result.exitCode, stderr: result.stderr))
    }

    nonisolated private static func runGit(_ args: [String], at cwd: URL) -> CommandResult? {
        guard let git = CommandResolver.resolve("git") else { return nil }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: git)
        task.arguments = args
        task.currentDirectoryURL = cwd
        let stdout = Pipe()
        let stderr = Pipe()
        task.standardOutput = stdout
        task.standardError = stderr
        do {
            try task.run()
        } catch {
            return nil
        }
        task.waitUntilExit()
        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        return CommandResult(
            exitCode: task.terminationStatus,
            stdout: String(data: outData, encoding: .utf8) ?? "",
            stderr: String(data: errData, encoding: .utf8) ?? ""
        )
    }

    private struct CommandResult {
        let exitCode: Int32
        let stdout: String
        let stderr: String
    }
}

enum GitWorktreeError: Error, LocalizedError, Equatable {
    case gitNotFound
    case commandFailed(exitCode: Int32, stderr: String)

    var errorDescription: String? {
        switch self {
        case .gitNotFound:
            return String(localized: "git.error.not_found")
        case .commandFailed(let code, let stderr):
            let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                return String(format: String(localized: "git.error.exit_status"), code)
            }
            return trimmed
        }
    }
}
