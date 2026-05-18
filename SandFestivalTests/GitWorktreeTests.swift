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

    @Test("isGitRepo is false when .git is a gitlink pointing at a missing gitdir")
    func isGitRepoRejectsStaleGitlink() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let gitFile = dir.appendingPathComponent(".git")
        try "gitdir: /tmp/definitely-not-a-real-worktree-gitdir-\(UUID())\n"
            .write(to: gitFile, atomically: true, encoding: .utf8)
        #expect(GitWorktree.isGitRepo(at: dir) == false)
    }

    @Test("isGitRepo is false when .git is an unrelated file with no gitdir line")
    func isGitRepoRejectsNonGitlinkFile() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try "not a gitlink\n".write(
            to: dir.appendingPathComponent(".git"),
            atomically: true,
            encoding: .utf8
        )
        #expect(GitWorktree.isGitRepo(at: dir) == false)
    }

    @Test("isGitRepo follows a relative gitlink to a valid gitdir")
    func isGitRepoAcceptsRelativeGitlink() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        // Synthesize the shape `git worktree add` produces: a sibling
        // gitdir containing a HEAD file, and a relative gitlink pointing
        // at it from the worktree dir.
        let gitdir = dir.appendingPathComponent("siblingdir", isDirectory: true)
        try FileManager.default.createDirectory(at: gitdir, withIntermediateDirectories: true)
        try "ref: refs/heads/main\n".write(
            to: gitdir.appendingPathComponent("HEAD"),
            atomically: true,
            encoding: .utf8
        )
        try "gitdir: siblingdir\n".write(
            to: dir.appendingPathComponent(".git"),
            atomically: true,
            encoding: .utf8
        )
        #expect(GitWorktree.isGitRepo(at: dir))
    }

    @Test("isGitRepo recognizes a real worktree added via git")
    func isGitRepoTrueForRealWorktree() throws {
        guard hasGit() else { return }
        let workspace = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let sourceRepo = workspace.appendingPathComponent("source", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceRepo, withIntermediateDirectories: true)
        try runGit(["init", "-b", "main"], at: sourceRepo)
        try runGit(["commit", "--allow-empty", "-m", "initial"], at: sourceRepo, withIdentity: true)

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
        #expect(GitWorktree.isGitRepo(at: worktreePath))
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

    @Test("deleteBranch removes a branch after its worktree is gone")
    func deleteBranchAfterWorktreeRemoval() throws {
        guard hasGit() else { return }
        let workspace = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: workspace) }

        let sourceRepo = workspace.appendingPathComponent("source", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceRepo, withIntermediateDirectories: true)
        try runGit(["init", "-b", "main"], at: sourceRepo)
        try runGit(["commit", "--allow-empty", "-m", "initial"], at: sourceRepo, withIdentity: true)

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
        // Worktree must go away first — git refuses `branch -d` for a
        // branch that's checked out somewhere.
        let removeResult = GitWorktree.removeWorktree(
            worktreePath: worktreePath,
            sourceRepoPath: sourceRepo,
            force: false
        )
        guard case .success = removeResult else {
            Issue.record("removeWorktree failed: \(removeResult)")
            return
        }
        // A freshly-created branch with no commits beyond the base is
        // considered merged, so the non-force `-d` should accept it.
        let deleteResult = GitWorktree.deleteBranch(
            name: "feature/twin",
            sourceRepoPath: sourceRepo,
            force: false
        )
        if case .failure(let err) = deleteResult {
            Issue.record("deleteBranch failed: \(err)")
        }
        let branches = GitWorktree.listLocalBranches(at: sourceRepo)
        #expect(!branches.contains("feature/twin"))
    }

    @Test("deleteBranch with force removes an unmerged branch")
    func deleteBranchForceRemovesUnmerged() throws {
        guard hasGit() else { return }
        let workspace = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: workspace) }

        let sourceRepo = workspace.appendingPathComponent("source", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceRepo, withIntermediateDirectories: true)
        try runGit(["init", "-b", "main"], at: sourceRepo)
        try runGit(["commit", "--allow-empty", "-m", "initial"], at: sourceRepo, withIdentity: true)

        let worktreePath = workspace.appendingPathComponent("twin", isDirectory: true)
        _ = GitWorktree.addWorktree(
            newBranch: "feature/twin",
            newPath: worktreePath,
            base: "main",
            sourceRepoPath: sourceRepo
        )
        // Add an unmerged commit to the worktree so non-force delete refuses.
        try Data("hello".utf8).write(to: worktreePath.appendingPathComponent("note.txt"))
        try runGit(["add", "note.txt"], at: worktreePath)
        try runGit(["commit", "-m", "diverge"], at: worktreePath, withIdentity: true)

        // Removing the worktree needs --force because of the new commit.
        let removed = GitWorktree.removeWorktree(
            worktreePath: worktreePath,
            sourceRepoPath: sourceRepo,
            force: true
        )
        guard case .success = removed else {
            Issue.record("removeWorktree --force failed: \(removed)")
            return
        }
        // Non-force branch delete must refuse the unmerged branch.
        let softDelete = GitWorktree.deleteBranch(
            name: "feature/twin",
            sourceRepoPath: sourceRepo,
            force: false
        )
        if case .success = softDelete {
            Issue.record("expected non-force deleteBranch to refuse unmerged branch")
        }
        // Force should succeed.
        let forced = GitWorktree.deleteBranch(
            name: "feature/twin",
            sourceRepoPath: sourceRepo,
            force: true
        )
        if case .failure(let err) = forced {
            Issue.record("force deleteBranch failed: \(err)")
        }
        let branches = GitWorktree.listLocalBranches(at: sourceRepo)
        #expect(!branches.contains("feature/twin"))
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

    @Test("ensureWorktreesIgnored creates .gitignore when missing")
    func ensureWorktreesIgnoredCreatesFile() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let gitignore = dir.appendingPathComponent(".gitignore")
        #expect(!FileManager.default.fileExists(atPath: gitignore.path))

        GitWorktree.ensureWorktreesIgnored(at: dir)

        let contents = try String(contentsOf: gitignore, encoding: .utf8)
        #expect(contents == ".worktrees/\n")
    }

    @Test("ensureWorktreesIgnored appends when existing gitignore lacks entry")
    func ensureWorktreesIgnoredAppendsEntry() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let gitignore = dir.appendingPathComponent(".gitignore")
        try "build/\n*.log\n".write(to: gitignore, atomically: true, encoding: .utf8)

        GitWorktree.ensureWorktreesIgnored(at: dir)

        let contents = try String(contentsOf: gitignore, encoding: .utf8)
        #expect(contents == "build/\n*.log\n.worktrees/\n")
    }

    @Test("ensureWorktreesIgnored inserts a newline before appending when missing")
    func ensureWorktreesIgnoredFixesMissingTrailingNewline() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let gitignore = dir.appendingPathComponent(".gitignore")
        // No trailing newline — common when the file was hand-edited.
        try "build/".write(to: gitignore, atomically: true, encoding: .utf8)

        GitWorktree.ensureWorktreesIgnored(at: dir)

        let contents = try String(contentsOf: gitignore, encoding: .utf8)
        #expect(contents == "build/\n.worktrees/\n")
    }

    @Test("ensureWorktreesIgnored is a no-op when entry already present")
    func ensureWorktreesIgnoredIsIdempotent() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let gitignore = dir.appendingPathComponent(".gitignore")
        let original = "build/\n.worktrees/\n*.log\n"
        try original.write(to: gitignore, atomically: true, encoding: .utf8)

        GitWorktree.ensureWorktreesIgnored(at: dir)
        // Run a second time to confirm idempotency under back-to-back calls.
        GitWorktree.ensureWorktreesIgnored(at: dir)

        let contents = try String(contentsOf: gitignore, encoding: .utf8)
        #expect(contents == original)
    }

    @Test("ensureWorktreesIgnored recognizes equivalent ignore patterns")
    func ensureWorktreesIgnoredRecognizesVariants() throws {
        let variants = [
            ".worktrees",
            ".worktrees/",
            "/.worktrees",
            "/.worktrees/",
            ".worktrees/*",
            ".worktrees/**",
            "/.worktrees/*",
            "/.worktrees/**",
        ]
        for variant in variants {
            let dir = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let gitignore = dir.appendingPathComponent(".gitignore")
            let original = "build/\n\(variant)\n"
            try original.write(to: gitignore, atomically: true, encoding: .utf8)

            GitWorktree.ensureWorktreesIgnored(at: dir)

            let contents = try String(contentsOf: gitignore, encoding: .utf8)
            #expect(contents == original, "variant \(variant) should be recognized as already covered")
        }
    }

    @Test("ensureWorktreesIgnored ignores commented-out entries")
    func ensureWorktreesIgnoredSkipsCommentedEntries() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let gitignore = dir.appendingPathComponent(".gitignore")
        // The comment looks like a covering pattern but git ignores it,
        // so we should still append a real entry.
        try "# .worktrees/\nbuild/\n".write(to: gitignore, atomically: true, encoding: .utf8)

        GitWorktree.ensureWorktreesIgnored(at: dir)

        let contents = try String(contentsOf: gitignore, encoding: .utf8)
        #expect(contents == "# .worktrees/\nbuild/\n.worktrees/\n")
    }

    @Test("ensureWorktreesIgnored does not accept unrelated patterns starting with .worktrees")
    func ensureWorktreesIgnoredRejectsNearMisses() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let gitignore = dir.appendingPathComponent(".gitignore")
        // Suffix is part of the path segment, so this only ignores a
        // specifically-named file — not the directory we want to cover.
        try ".worktrees-backup/\n".write(to: gitignore, atomically: true, encoding: .utf8)

        GitWorktree.ensureWorktreesIgnored(at: dir)

        let contents = try String(contentsOf: gitignore, encoding: .utf8)
        #expect(contents == ".worktrees-backup/\n.worktrees/\n")
    }

    @Test("listInUseBranches returns the primary repo's HEAD branch")
    func listInUseBranchesIncludesPrimary() throws {
        guard hasGit() else { return }
        let workspace = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: workspace) }

        let sourceRepo = workspace.appendingPathComponent("source", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceRepo, withIntermediateDirectories: true)
        try runGit(["init", "-b", "main"], at: sourceRepo)
        try runGit(["commit", "--allow-empty", "-m", "initial"], at: sourceRepo, withIdentity: true)

        let inUse = GitWorktree.listInUseBranches(at: sourceRepo)
        #expect(inUse.contains("main"))
    }

    @Test("listInUseBranches sees branches checked out in linked worktrees too")
    func listInUseBranchesIncludesLinkedWorktrees() throws {
        guard hasGit() else { return }
        let workspace = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: workspace) }

        let sourceRepo = workspace.appendingPathComponent("source", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceRepo, withIntermediateDirectories: true)
        try runGit(["init", "-b", "main"], at: sourceRepo)
        try runGit(["commit", "--allow-empty", "-m", "initial"], at: sourceRepo, withIdentity: true)

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

        let inUse = GitWorktree.listInUseBranches(at: sourceRepo)
        #expect(inUse.contains("main"))
        #expect(inUse.contains("feature/twin"))

        // A branch that exists locally but isn't checked out anywhere
        // shouldn't appear.
        try runGit(["branch", "parked"], at: sourceRepo)
        let inUseAfter = GitWorktree.listInUseBranches(at: sourceRepo)
        #expect(!inUseAfter.contains("parked"))
    }

    @Test("checkoutWorktree creates a worktree for an existing branch without changing HEAD")
    func checkoutWorktreeExistingBranch() throws {
        guard hasGit() else { return }
        let workspace = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: workspace) }

        let sourceRepo = workspace.appendingPathComponent("source", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceRepo, withIntermediateDirectories: true)
        try runGit(["init", "-b", "main"], at: sourceRepo)
        try runGit(["commit", "--allow-empty", "-m", "initial"], at: sourceRepo, withIdentity: true)
        // A branch that's NOT currently checked out anywhere — the duplicate
        // flow's "continue work on an existing branch" path is exactly this.
        try runGit(["branch", "feature/parked"], at: sourceRepo)

        let worktreePath = workspace.appendingPathComponent("twin", isDirectory: true)
        let result = GitWorktree.checkoutWorktree(
            existingBranch: "feature/parked",
            newPath: worktreePath,
            sourceRepoPath: sourceRepo
        )
        guard case .success = result else {
            Issue.record("checkoutWorktree failed: \(result)")
            return
        }
        #expect(FileManager.default.fileExists(atPath: worktreePath.path))
        // listLocalBranches shouldn't gain a new branch — we checked out an
        // existing one, not created a new one.
        let branches = GitWorktree.listLocalBranches(at: sourceRepo)
        #expect(branches.contains("feature/parked"))
        #expect(branches.count == 2) // main + feature/parked
        // And feature/parked is now in use.
        let inUse = GitWorktree.listInUseBranches(at: sourceRepo)
        #expect(inUse.contains("feature/parked"))
    }

    @Test("checkoutWorktree refuses a branch that's already checked out elsewhere")
    func checkoutWorktreeRefusesInUseBranch() throws {
        guard hasGit() else { return }
        let workspace = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: workspace) }

        let sourceRepo = workspace.appendingPathComponent("source", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceRepo, withIntermediateDirectories: true)
        try runGit(["init", "-b", "main"], at: sourceRepo)
        try runGit(["commit", "--allow-empty", "-m", "initial"], at: sourceRepo, withIdentity: true)

        // `main` is the primary worktree's HEAD — git should refuse.
        let worktreePath = workspace.appendingPathComponent("twin", isDirectory: true)
        let result = GitWorktree.checkoutWorktree(
            existingBranch: "main",
            newPath: worktreePath,
            sourceRepoPath: sourceRepo
        )
        switch result {
        case .success:
            Issue.record("expected checkoutWorktree to fail for in-use branch")
        case .failure(let err):
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
