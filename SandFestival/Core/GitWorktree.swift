import Foundation

/// Thin wrapper around `git worktree` and `git branch` calls used by the
/// project-duplicate flow. Functions are `nonisolated` so callers on the
/// MainActor can hop to a background `Task` for the blocking
/// `Process.waitUntilExit()`.
enum GitWorktree {
    /// True when `path` looks like a git working tree (regular repo *or*
    /// an existing worktree). A regular repo has `.git` as a directory
    /// containing `HEAD`; a linked worktree has `.git` as a gitlink file
    /// `gitdir: <path>` pointing at the worktree's per-worktree gitdir,
    /// which also contains `HEAD`. We resolve the gitlink and verify a
    /// `HEAD` exists at the target so stale gitlinks (worktree gitdir
    /// deleted out from under us) and unrelated `.git` files don't pass.
    static func isGitRepo(at path: URL) -> Bool {
        let fm = FileManager.default
        let gitURL = path.appendingPathComponent(".git")
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: gitURL.path, isDirectory: &isDir) else { return false }

        let gitDir: URL
        if isDir.boolValue {
            gitDir = gitURL
        } else {
            guard let contents = try? String(contentsOf: gitURL, encoding: .utf8) else {
                return false
            }
            let prefix = "gitdir:"
            let target = contents
                .split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .first { $0.hasPrefix(prefix) }
                .map { String($0.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces) }
            guard let target, !target.isEmpty else { return false }
            if target.hasPrefix("/") {
                gitDir = URL(fileURLWithPath: target)
            } else {
                gitDir = URL(fileURLWithPath: target, relativeTo: path).standardizedFileURL
            }
        }
        return fm.fileExists(atPath: gitDir.appendingPathComponent("HEAD").path)
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

    /// Idempotently ensures `.worktrees/` is listed in the source repo's
    /// `.gitignore`. Creates the file if missing, leaves it alone if a
    /// covering entry is already present, and is silent on I/O failure —
    /// gitignore hygiene is a nicety, not load-bearing for the worktree
    /// itself, so we don't want to surface errors that would block the
    /// project creation flow.
    nonisolated static func ensureWorktreesIgnored(at repoPath: URL) {
        let gitignore = repoPath.appendingPathComponent(".gitignore")
        let existing: String
        if let data = try? Data(contentsOf: gitignore),
           let text = String(data: data, encoding: .utf8) {
            existing = text
            // Match the shapes that effectively ignore `.worktrees/` at the
            // repo root: bare, slash-prefixed, trailing slash, and the
            // `/*`/`/**` glob suffixes people use when their tooling prefers
            // explicit children. Comment lines are skipped before matching.
            let pattern = /^\/?\.worktrees(?:\/(?:\*{1,2})?)?$/
            let alreadyHas = text
                .split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .contains(where: { line in
                    guard !line.isEmpty, !line.hasPrefix("#") else { return false }
                    return line.wholeMatch(of: pattern) != nil
                })
            if alreadyHas { return }
        } else {
            existing = ""
        }
        let separator = existing.isEmpty || existing.hasSuffix("\n") ? "" : "\n"
        let appended = existing + separator + ".worktrees/\n"
        try? appended.write(to: gitignore, atomically: true, encoding: .utf8)
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
