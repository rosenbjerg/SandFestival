import Foundation
import Testing
@testable import SandFestival

/// Integration test: spins up a real git repo in a temp directory and
/// exercises add/remove/listLocalBranches. Skipped automatically if
/// `git` isn't on PATH so CI environments without git don't fail.
@Suite("GitWorktree integration")
struct GitWorktreeTests {

    @Test("isGitRepo is false for an unrelated directory")
    func isGitRepoFalseForPlainDir() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(GitWorktree.isGitRepo(at: dir) == false)
    }

    @Test("end-to-end: init repo, list branches, add worktree, remove worktree")
    func endToEnd() throws {
        guard hasGit() else { return }
        let workspace = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: workspace) }

        let sourceRepo = workspace.appendingPathComponent("source", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceRepo, withIntermediateDirectories: true)

        try runGit(["init", "-b", "main"], at: sourceRepo)
        try runGit(["commit", "--allow-empty", "-m", "initial"], at: sourceRepo, withIdentity: true)

        #expect(GitWorktree.isGitRepo(at: sourceRepo))

        let branches = GitWorktree.listLocalBranches(at: sourceRepo)
        #expect(branches.contains("main"))

        let worktreePath = workspace.appendingPathComponent("twin", isDirectory: true)
        let addResult = GitWorktree.addWorktree(
            newBranch: "feature/twin",
            newPath: worktreePath,
            base: "main",
            sourceRepoPath: sourceRepo
        )
        guard case .success = addResult else {
            Issue.record("addWorktree failed: \(addResult)")
            return
        }
        #expect(FileManager.default.fileExists(atPath: worktreePath.path))
        // The new branch should now appear in the list.
        let branchesAfterAdd = GitWorktree.listLocalBranches(at: sourceRepo)
        #expect(branchesAfterAdd.contains("feature/twin"))

        let removeResult = GitWorktree.removeWorktree(
            worktreePath: worktreePath,
            sourceRepoPath: sourceRepo,
            force: false
        )
        guard case .success = removeResult else {
            Issue.record("removeWorktree failed: \(removeResult)")
            return
        }
        #expect(!FileManager.default.fileExists(atPath: worktreePath.path))
    }

    @Test("addWorktree surfaces git stderr when the target path already exists")
    func addWorktreeReportsConflict() throws {
        guard hasGit() else { return }
        let workspace = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: workspace) }

        let sourceRepo = workspace.appendingPathComponent("source", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceRepo, withIntermediateDirectories: true)
        try runGit(["init", "-b", "main"], at: sourceRepo)
        try runGit(["commit", "--allow-empty", "-m", "initial"], at: sourceRepo, withIdentity: true)

        // Pre-create the worktree path with a file inside so `git worktree add`
        // refuses — git happily accepts *empty* directories, the conflict only
        // triggers when there's existing content.
        let worktreePath = workspace.appendingPathComponent("twin", isDirectory: true)
        try FileManager.default.createDirectory(at: worktreePath, withIntermediateDirectories: true)
        try Data("blocker".utf8).write(to: worktreePath.appendingPathComponent("file.txt"))

        let result = GitWorktree.addWorktree(
            newBranch: "feature/twin",
            newPath: worktreePath,
            base: nil,
            sourceRepoPath: sourceRepo
        )
        switch result {
        case .success:
            Issue.record("expected addWorktree to fail for existing path")
        case .failure(let err):
            // Pass when we got *any* git error description — the exact
            // wording is git-version-dependent.
            #expect(err.errorDescription?.isEmpty == false)
        }
    }

    // MARK: - Helpers

    private func hasGit() -> Bool {
        // Soft-skip: tests bail out silently on CI/dev machines without git.
        CommandResolver.resolve("git") != nil
    }

    private struct GitNotInstalled: Error {}

    private func makeTempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitWorktreeTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Runs git in `cwd`. When `withIdentity` is true, injects author/committer
    /// env so `git commit` works without a system-level git config.
    private func runGit(_ args: [String], at cwd: URL, withIdentity: Bool = false) throws {
        guard let git = CommandResolver.resolve("git") else { throw GitNotInstalled() }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: git)
        task.arguments = args
        task.currentDirectoryURL = cwd
        if withIdentity {
            var env = ProcessInfo.processInfo.environment
            env["GIT_AUTHOR_NAME"] = "Test"
            env["GIT_AUTHOR_EMAIL"] = "test@example.com"
            env["GIT_COMMITTER_NAME"] = "Test"
            env["GIT_COMMITTER_EMAIL"] = "test@example.com"
            task.environment = env
        }
        let stderr = Pipe()
        task.standardError = stderr
        task.standardOutput = Pipe()
        try task.run()
        task.waitUntilExit()
        if task.terminationStatus != 0 {
            let data = stderr.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8) ?? ""
            throw GitCommandFailed(args: args, stderr: message)
        }
    }

    private struct GitCommandFailed: Error, CustomStringConvertible {
        let args: [String]
        let stderr: String
        var description: String { "git \(args.joined(separator: " ")) failed: \(stderr)" }
    }
}
