import Foundation

/// Thin wrapper around `git worktree` and `git branch` calls used by the
/// project-duplicate flow. Functions are `nonisolated` so callers on the
/// MainActor can hop to a background `Task` for the blocking
/// `Process.waitUntilExit()`.
enum GitWorktree {
    /// True when a `git` binary is reachable on PATH. Cheap — just a
    /// filesystem stat per search-path entry, no subprocess. Used by the
    /// duplicate sheet to hide the Worktree section entirely when there's
    /// no point offering it: every git-backed mutation would fail with
    /// `.gitNotFound` on submit anyway, and `listLocalBranches` would
    /// silently return empty in the meantime.
    static func isGitInstalled() -> Bool {
        CommandResolver.resolve("git") != nil
    }

    /// Conservative check that `name` is a usable `git branch` name, so the
    /// duplicate sheet can reject a doomed name keystroke-by-keystroke
    /// instead of letting `git worktree add -b` fail at submit. Pure — no
    /// subprocess. Mirrors the subset of `git check-ref-format` rules a user
    /// is likely to trip over by hand; `git` itself remains the final word.
    static func isValidBranchName(_ name: String) -> Bool {
        guard !name.isEmpty, name != "@" else { return false }
        guard !name.hasPrefix("-"), !name.hasPrefix("/"), !name.hasSuffix("/") else { return false }
        guard !name.hasSuffix("."), !name.hasSuffix(".lock") else { return false }
        guard !name.contains(".."), !name.contains("//"), !name.contains("@{") else { return false }
        let forbidden: Set<Character> = [" ", "~", "^", ":", "?", "*", "[", "\\", "\u{7f}"]
        for character in name {
            if forbidden.contains(character) { return false }
            if let scalar = character.unicodeScalars.first, scalar.value < 0x20 { return false }
        }
        // No slash-separated component may begin with "." or end with ".lock".
        for component in name.split(separator: "/", omittingEmptySubsequences: false) {
            if component.hasPrefix(".") || component.hasSuffix(".lock") { return false }
        }
        return true
    }

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

    /// Remote-tracking branch names (`origin/main`) in `git branch -r` order.
    /// `origin/HEAD` is dropped: it's a symref onto the remote's default
    /// branch, not something a user would pick by name.
    nonisolated static func listRemoteBranches(at path: URL) -> [String] {
        guard let result = runGit(["branch", "--remotes", "--format=%(refname:short)"], at: path),
              result.exitCode == 0
        else { return [] }
        return result.stdout
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasSuffix("/HEAD") }
    }

    /// True when the repo has at least one remote configured. Tells "no
    /// remotes at all" apart from "remotes we've never fetched" — both show
    /// an empty remote branch list, and only the second is worth offering a
    /// Fetch button for.
    nonisolated static func hasRemotes(at path: URL) -> Bool {
        guard let result = runGit(["remote"], at: path), result.exitCode == 0 else { return false }
        return result.stdout.contains { !$0.isWhitespace }
    }

    /// The local branch name a remote-tracking ref maps onto — everything
    /// after the remote name. `origin/feat/foo` → `feat/foo`.
    static func localName(forRemoteRef ref: String) -> String {
        guard let slash = ref.firstIndex(of: "/") else { return ref }
        return String(ref[ref.index(after: slash)...])
    }

    /// When the repo last fetched, from `FETCH_HEAD`'s mtime, or `nil` if it
    /// never has. Lets the duplicate sheet say how stale its remote branch
    /// list is without paying for a network round trip.
    nonisolated static func lastFetchDate(at path: URL) -> Date? {
        guard let result = runGit(["rev-parse", "--git-path", "FETCH_HEAD"], at: path),
              result.exitCode == 0
        else { return nil }
        let raw = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        let url = raw.hasPrefix("/")
            ? URL(fileURLWithPath: raw)
            : URL(fileURLWithPath: raw, relativeTo: path)
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return attributes?[.modificationDate] as? Date
    }

    /// `git fetch --prune`. The only call in this file that touches the
    /// network, so the only one carrying a deadline — an unreachable host
    /// would otherwise wedge the sheet's refresh indefinitely.
    nonisolated static func fetch(
        at path: URL,
        timeout: TimeInterval = 20
    ) -> Result<Void, GitWorktreeError> {
        runChecked(["fetch", "--prune"], at: path, timeout: timeout)
    }

    /// Everything the duplicate sheet needs to know about a repo's branches.
    struct BranchSnapshot: Equatable {
        var local: [String] = []
        var remote: [String] = []
        var inUse: Set<String> = []
        var hasRemotes: Bool = false
        var lastFetch: Date?
    }

    /// Gathers the whole snapshot in one hop off the main actor. SwiftUI view
    /// construction blocks on `waitUntilExit()` otherwise, jamming the runloop
    /// while the system is trying to present the sheet — same shape as the
    /// `NonoProfileDiscovery.availableProfilesAsync` fix.
    static func loadBranchSnapshot(at path: URL) async -> BranchSnapshot {
        await Task.detached(priority: .userInitiated) {
            let remotesConfigured = hasRemotes(at: path)
            return BranchSnapshot(
                local: listLocalBranches(at: path),
                remote: remotesConfigured ? listRemoteBranches(at: path) : [],
                inUse: listInUseBranches(at: path),
                hasRemotes: remotesConfigured,
                lastFetch: remotesConfigured ? lastFetchDate(at: path) : nil
            )
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

    /// `git worktree add <newPath> <existingBranch>` from `sourceRepoPath`.
    /// Used by the duplicate flow's "continue work on an existing branch" mode.
    /// Git refuses if the branch is already checked out in another worktree —
    /// we filter those out in the picker but the caller still surfaces the
    /// error if a race slips one through.
    nonisolated static func checkoutWorktree(
        existingBranch: String,
        newPath: URL,
        sourceRepoPath: URL
    ) -> Result<Void, GitWorktreeError> {
        let args = ["worktree", "add", newPath.path, existingBranch]
        return runChecked(args, at: sourceRepoPath)
    }

    /// `git worktree add --track -b <localBranch> <newPath> <remoteRef>` from
    /// `sourceRepoPath`. A bare `git worktree add <path> origin/feat` checks
    /// out a *detached HEAD* rather than a branch tracking the remote, which
    /// is never what "continue work on this branch" is asking for — so
    /// picking a remote ref has to create the local branch explicitly.
    nonisolated static func checkoutRemoteWorktree(
        remoteRef: String,
        localBranch: String,
        newPath: URL,
        sourceRepoPath: URL
    ) -> Result<Void, GitWorktreeError> {
        let args = ["worktree", "add", "--track", "-b", localBranch, newPath.path, remoteRef]
        return runChecked(args, at: sourceRepoPath)
    }

    /// Branch short-names currently checked out in any worktree of this repo
    /// (including the primary working tree). `git worktree add` refuses a
    /// branch that's in use elsewhere, so the duplicate picker uses this to
    /// disable those rows. Empty set on parse failure — caller still sees the
    /// branch as selectable and gets the git error if they actually pick it.
    nonisolated static func listInUseBranches(at sourceRepoPath: URL) -> Set<String> {
        guard let result = runGit(["worktree", "list", "--porcelain"], at: sourceRepoPath),
              result.exitCode == 0
        else { return [] }
        // Each `branch refs/heads/<name>` line marks a worktree that has that
        // branch checked out. Detached-HEAD worktrees produce a `detached`
        // line instead, which we ignore.
        let prefix = "branch refs/heads/"
        var names = Set<String>()
        for line in result.stdout.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix(prefix) else { continue }
            let name = String(trimmed.dropFirst(prefix.count))
            if !name.isEmpty { names.insert(name) }
        }
        return names
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

    /// `git branch -d|-D <name>` from `sourceRepoPath`. `force: false` uses
    /// `-d` so git refuses to delete an unmerged branch; `force: true` uses
    /// `-D` and discards unmerged work. Callers should only invoke this
    /// once the worktree that held the branch has been removed — `-d`
    /// refuses to delete a branch that's currently checked out elsewhere.
    nonisolated static func deleteBranch(
        name: String,
        sourceRepoPath: URL,
        force: Bool
    ) -> Result<Void, GitWorktreeError> {
        let flag = force ? "-D" : "-d"
        return runChecked(["branch", flag, name], at: sourceRepoPath)
    }

    // MARK: - Internals

    nonisolated private static func runChecked(
        _ args: [String],
        at cwd: URL,
        timeout: TimeInterval? = nil
    ) -> Result<Void, GitWorktreeError> {
        guard let result = runGit(args, at: cwd, timeout: timeout) else {
            return .failure(.gitNotFound)
        }
        if result.timedOut { return .failure(.timedOut) }
        if result.exitCode == 0 { return .success(()) }
        return .failure(.commandFailed(exitCode: result.exitCode, stderr: result.stderr))
    }

    nonisolated private static func runGit(
        _ args: [String],
        at cwd: URL,
        timeout: TimeInterval? = nil
    ) -> CommandResult? {
        guard let git = CommandResolver.resolve("git") else { return nil }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: git)
        task.arguments = args
        task.currentDirectoryURL = cwd
        // No terminal is attached, so a credential or passphrase prompt would
        // block until the deadline instead of failing fast. Fetch is the call
        // that can provoke one.
        var environment = ProcessInfo.processInfo.environment
        environment["GIT_TERMINAL_PROMPT"] = "0"
        task.environment = environment
        let stdout = Pipe()
        let stderr = Pipe()
        task.standardOutput = stdout
        task.standardError = stderr
        do {
            try task.run()
        } catch {
            return nil
        }
        // Terminating the child is what unblocks the reads below — there's no
        // way to interrupt `readDataToEndOfFile` directly.
        let watchdog = TimeoutWatchdog()
        if let timeout {
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                guard watchdog.expire() else { return }
                task.terminate()
            }
        }
        // Drain both pipes concurrently before waiting. If the child outgrows
        // the ~64 KB pipe buffer on either stream it blocks on write — and a
        // `waitUntilExit()` before reading would then deadlock against it.
        let errDrain = PipeDrain(handle: stderr.fileHandleForReading)
        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = errDrain.wait()
        task.waitUntilExit()
        _ = watchdog.finish()
        return CommandResult(
            exitCode: task.terminationStatus,
            stdout: String(data: outData, encoding: .utf8) ?? "",
            stderr: String(data: errData, encoding: .utf8) ?? "",
            timedOut: watchdog.didExpire
        )
    }

    private struct CommandResult {
        let exitCode: Int32
        let stdout: String
        let stderr: String
        var timedOut: Bool = false
    }

    /// Decides the race between the timeout firing and the process exiting on
    /// its own. `DispatchWorkItem.cancel()` can't stop an item already running,
    /// so without a claim the watchdog could signal a pid Foundation has
    /// already reaped — and pids get recycled. Whoever takes the lock first
    /// wins; the loser does nothing.
    private nonisolated final class TimeoutWatchdog: @unchecked Sendable {
        private let lock = NSLock()
        private var settled = false
        /// Only written by the winning claim, and only read once `finish()`
        /// has returned — by which point no further writes are possible.
        private(set) var didExpire = false

        func expire() -> Bool { claim(expired: true) }

        func finish() -> Bool { claim(expired: false) }

        private func claim(expired: Bool) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            if settled { return false }
            settled = true
            didExpire = expired
            return true
        }
    }

    /// Reads a pipe to EOF on a background queue so a sibling pipe can be
    /// drained concurrently on the calling thread — neither child stream can
    /// fill its buffer and wedge the process while the other is read. All
    /// access to `data` is confined to `queue`, so the `@unchecked` is sound.
    private nonisolated final class PipeDrain: @unchecked Sendable {
        private let handle: FileHandle
        private var data = Data()
        private let queue = DispatchQueue(label: "app.sandfestival.gitworktree.pipe-drain")

        init(handle: FileHandle) {
            self.handle = handle
            queue.async { self.data = self.handle.readDataToEndOfFile() }
        }

        /// Blocks until the background read finishes, then returns the bytes.
        func wait() -> Data {
            queue.sync { data }
        }
    }
}

/// A branch the duplicate sheet can offer, tagged with where it came from.
/// `name` is what git is given verbatim, so a remote ref carries its remote
/// prefix (`origin/main`).
struct GitRef: Hashable {
    enum Kind: Hashable {
        case local
        case remote
    }

    let name: String
    let kind: Kind
}

enum GitWorktreeError: Error, LocalizedError, Equatable {
    case gitNotFound
    case timedOut
    case commandFailed(exitCode: Int32, stderr: String)

    var errorDescription: String? {
        switch self {
        case .gitNotFound:
            return String(localized: "git.error.not_found")
        case .timedOut:
            return String(localized: "git.error.timed_out")
        case .commandFailed(let code, let stderr):
            let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                return String(format: String(localized: "git.error.exit_status"), code)
            }
            return trimmed
        }
    }
}
