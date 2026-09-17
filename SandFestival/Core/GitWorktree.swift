import Foundation

enum GitWorktree {
    static func isGitInstalled() -> Bool {
        CommandResolver.resolve("git") != nil
    }

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
        for component in name.split(separator: "/", omittingEmptySubsequences: false) {
            if component.hasPrefix(".") || component.hasSuffix(".lock") { return false }
        }
        return true
    }

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

    nonisolated static func listLocalBranches(at path: URL) -> [String] {
        guard let result = runGit(["branch", "--format=%(refname:short)"], at: path),
              result.exitCode == 0
        else { return [] }
        return result.stdout
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    nonisolated static func listRemoteBranches(at path: URL) -> [String] {
        guard let result = runGit(["branch", "--remotes", "--format=%(refname:short)"], at: path),
              result.exitCode == 0
        else { return [] }
        return result.stdout
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasSuffix("/HEAD") }
    }

    nonisolated static func hasRemotes(at path: URL) -> Bool {
        guard let result = runGit(["remote"], at: path), result.exitCode == 0 else { return false }
        return result.stdout.contains { !$0.isWhitespace }
    }

    static func localName(forRemoteRef ref: String) -> String {
        guard let slash = ref.firstIndex(of: "/") else { return ref }
        return String(ref[ref.index(after: slash)...])
    }

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

    nonisolated static func fetch(
        at path: URL,
        timeout: TimeInterval = 20
    ) -> Result<Void, GitWorktreeError> {
        runChecked(["fetch", "--prune"], at: path, timeout: timeout)
    }

    struct BranchSnapshot: Equatable {
        var local: [String] = []
        var remote: [String] = []
        var inUse: Set<String> = []
        var hasRemotes: Bool = false
        var lastFetch: Date?
    }

    static func loadBranchSnapshot(at path: URL) async -> BranchSnapshot {
        // Detached: the waitUntilExit() calls inside would otherwise block the
        // main actor while the sheet is presenting.
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

    nonisolated static func checkoutWorktree(
        existingBranch: String,
        newPath: URL,
        sourceRepoPath: URL
    ) -> Result<Void, GitWorktreeError> {
        let args = ["worktree", "add", newPath.path, existingBranch]
        return runChecked(args, at: sourceRepoPath)
    }

    // Without `--track -b`, adding a remote ref checks out a detached HEAD.
    nonisolated static func checkoutRemoteWorktree(
        remoteRef: String,
        localBranch: String,
        newPath: URL,
        sourceRepoPath: URL
    ) -> Result<Void, GitWorktreeError> {
        let args = ["worktree", "add", "--track", "-b", localBranch, newPath.path, remoteRef]
        return runChecked(args, at: sourceRepoPath)
    }

    nonisolated static func listInUseBranches(at sourceRepoPath: URL) -> Set<String> {
        guard let result = runGit(["worktree", "list", "--porcelain"], at: sourceRepoPath),
              result.exitCode == 0
        else { return [] }
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

    nonisolated static func status(at path: URL, base: String? = nil) -> GitStatusResult {
        guard let result = runGit(
            ["--no-optional-locks", "status", "--porcelain=v2", "--branch"],
            at: path
        ), result.exitCode == 0
        else { return .unavailable }
        var status = GitStatus.parse(porcelainV2: result.stdout)
        if let base, !base.isEmpty, let divergence = divergence(from: base, at: path) {
            status.ahead = divergence.ahead
            status.behind = divergence.behind
            status.comparisonRef = base
        }
        return .status(status)
    }

    nonisolated static func divergence(
        from base: String,
        at path: URL
    ) -> (ahead: Int, behind: Int)? {
        guard let result = runGit(
            ["rev-list", "--left-right", "--count", "\(base)...HEAD"],
            at: path
        ), result.exitCode == 0
        else { return nil }
        let fields = result.stdout.split(whereSeparator: { $0 == "\t" || $0 == " " || $0.isNewline })
        // --left-right prints <base-only> then <HEAD-only>: left is behind, right is ahead.
        guard fields.count >= 2, let behind = Int(fields[0]), let ahead = Int(fields[1]) else {
            return nil
        }
        return (ahead: ahead, behind: behind)
    }

    nonisolated static func ensureWorktreesIgnored(at repoPath: URL) {
        let gitignore = repoPath.appendingPathComponent(".gitignore")
        let existing: String
        if let data = try? Data(contentsOf: gitignore),
           let text = String(data: data, encoding: .utf8) {
            existing = text
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

    nonisolated static func deleteBranch(
        name: String,
        sourceRepoPath: URL,
        force: Bool
    ) -> Result<Void, GitWorktreeError> {
        let flag = force ? "-D" : "-d"
        return runChecked(["branch", flag, name], at: sourceRepoPath)
    }

    nonisolated static func initRepository(at path: URL) -> Result<Void, GitWorktreeError> {
        do {
            try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
        } catch {
            return .failure(.cannotCreateDirectory(
                path: path.path,
                reason: error.localizedDescription
            ))
        }
        return runChecked(["init"], at: path)
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
        // A credential prompt would otherwise hang fetch until the deadline.
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
        let watchdog = TimeoutWatchdog()
        if let timeout {
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                guard watchdog.expire() else { return }
                task.terminate()
            }
        }
        // Both streams concurrently, and before waitUntilExit(): a child that
        // fills a 64 KB pipe blocks on write, and waiting first deadlocks on it.
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

    // A claim, not DispatchWorkItem.cancel(): cancel can't stop a running item,
    // and terminate() after Foundation reaped the pid may hit a recycled one.
    private nonisolated final class TimeoutWatchdog: @unchecked Sendable {
        private let lock = NSLock()
        private var settled = false
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

    private nonisolated final class PipeDrain: @unchecked Sendable {
        private let handle: FileHandle
        private var data = Data()
        private let queue = DispatchQueue(label: "app.sandfestival.gitworktree.pipe-drain")

        init(handle: FileHandle) {
            self.handle = handle
            queue.async { self.data = self.handle.readDataToEndOfFile() }
        }

        func wait() -> Data {
            queue.sync { data }
        }
    }
}

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
    case cannotCreateDirectory(path: String, reason: String)

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
        case .cannotCreateDirectory(let path, let reason):
            return String(format: String(localized: "git.error.cannot_create_directory"), path, reason)
        }
    }
}
