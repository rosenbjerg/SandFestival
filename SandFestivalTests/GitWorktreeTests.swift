import Foundation
import Testing
@testable import SandFestival

@Suite("GitWorktree integration")
struct GitWorktreeTests {

    @Test("isValidBranchName accepts ordinary names and rejects malformed ones")
    func branchNameValidation() {
        for name in ["main", "feature-x", "fix/bug-123", "release_2.0", "wip"] {
            #expect(GitWorktree.isValidBranchName(name), "\(name) should be valid")
        }
        for name in [
            "", "@", "has space", "-leading-dash", "trailing.lock",
            "double..dot", "ends-with-dot.", "/leading-slash", "trailing-slash/",
            "bad~char", "colon:name", "star*name", ".dotcomponent", "a//b",
        ] {
            #expect(!GitWorktree.isValidBranchName(name), "\(name) should be rejected")
        }
    }

    @Test("initRepository creates a missing directory and makes it a repo")
    func initRepositoryCreatesDirectory() throws {
        guard hasGit() else { return }
        let parent = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: parent) }
        let repo = parent.appendingPathComponent("nested/new-repo", isDirectory: true)

        let result = GitWorktree.initRepository(at: repo)

        if case .failure(let error) = result {
            Issue.record("initRepository failed: \(error)")
        }
        #expect(GitWorktree.isGitRepo(at: repo))
    }

    @Test("initRepository over an existing repo leaves its branches intact")
    func initRepositoryIsIdempotent() throws {
        guard hasGit() else { return }
        let repo = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: repo) }
        try runGit(["init"], at: repo)
        try runGit(["commit", "--allow-empty", "-m", "initial"], at: repo, withIdentity: true)
        try runGit(["branch", "keepme"], at: repo)

        let result = GitWorktree.initRepository(at: repo)

        if case .failure(let error) = result {
            Issue.record("initRepository failed: \(error)")
        }
        #expect(GitWorktree.listLocalBranches(at: repo).contains("keepme"))
    }

    @Test("initRepository reports a path it can't create")
    func initRepositoryReportsCreationFailure() throws {
        let parent = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: parent) }
        let blocker = parent.appendingPathComponent("blocker")
        try "".write(to: blocker, atomically: true, encoding: .utf8)

        let result = GitWorktree.initRepository(at: blocker.appendingPathComponent("repo"))

        guard case .failure(.cannotCreateDirectory) = result else {
            Issue.record("expected .cannotCreateDirectory, got \(result)")
            return
        }
    }

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
        let removeResult = GitWorktree.removeWorktree(
            worktreePath: worktreePath,
            sourceRepoPath: sourceRepo,
            force: false
        )
        guard case .success = removeResult else {
            Issue.record("removeWorktree failed: \(removeResult)")
            return
        }
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
        try Data("hello".utf8).write(to: worktreePath.appendingPathComponent("note.txt"))
        try runGit(["add", "note.txt"], at: worktreePath)
        try runGit(["commit", "-m", "diverge"], at: worktreePath, withIdentity: true)

        let removed = GitWorktree.removeWorktree(
            worktreePath: worktreePath,
            sourceRepoPath: sourceRepo,
            force: true
        )
        guard case .success = removed else {
            Issue.record("removeWorktree --force failed: \(removed)")
            return
        }
        let softDelete = GitWorktree.deleteBranch(
            name: "feature/twin",
            sourceRepoPath: sourceRepo,
            force: false
        )
        if case .success = softDelete {
            Issue.record("expected non-force deleteBranch to refuse unmerged branch")
        }
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
            // Any description: the exact wording is git-version-dependent.
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
        let branches = GitWorktree.listLocalBranches(at: sourceRepo)
        #expect(branches.contains("feature/parked"))
        #expect(branches.count == 2)
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

    // MARK: - Remotes

    @Test("localName strips the remote prefix from a tracking ref")
    func localNameStripsRemotePrefix() {
        #expect(GitWorktree.localName(forRemoteRef: "origin/main") == "main")
        #expect(GitWorktree.localName(forRemoteRef: "origin/feat/foo") == "feat/foo")
        #expect(GitWorktree.localName(forRemoteRef: "upstream/main") == "main")
        #expect(GitWorktree.localName(forRemoteRef: "main") == "main")
    }

    @Test("hasRemotes tells a remote-less repo from one that just hasn't fetched")
    func hasRemotesDistinguishesUnfetched() throws {
        guard hasGit() else { return }
        let workspace = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: workspace) }

        let plain = workspace.appendingPathComponent("plain", isDirectory: true)
        try FileManager.default.createDirectory(at: plain, withIntermediateDirectories: true)
        try runGit(["init", "-b", "main"], at: plain)
        #expect(GitWorktree.hasRemotes(at: plain) == false)

        let repo = try makeRepoWithRemote(in: workspace)
        #expect(GitWorktree.hasRemotes(at: repo))
    }

    @Test("listRemoteBranches reports tracking refs and drops origin/HEAD")
    func listRemoteBranchesDropsSymref() throws {
        guard hasGit() else { return }
        let workspace = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let repo = try makeRepoWithRemote(in: workspace)
        try runGit(["branch", "feature/remote-only"], at: repo)
        try runGit(["push", "origin", "feature/remote-only"], at: repo)
        try runGit(["remote", "set-head", "origin", "main"], at: repo)

        let remotes = GitWorktree.listRemoteBranches(at: repo)
        #expect(remotes.contains("origin/main"))
        #expect(remotes.contains("origin/feature/remote-only"))
        #expect(!remotes.contains { $0.hasSuffix("/HEAD") })
    }

    @Test("fetch succeeds and stamps FETCH_HEAD")
    func fetchStampsLastFetchDate() throws {
        guard hasGit() else { return }
        let workspace = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let repo = try makeRepoWithRemote(in: workspace)
        #expect(GitWorktree.lastFetchDate(at: repo) == nil)

        let result = GitWorktree.fetch(at: repo)
        guard case .success = result else {
            Issue.record("fetch failed: \(result)")
            return
        }
        #expect(GitWorktree.lastFetchDate(at: repo) != nil)
    }

    @Test("the branch snapshot gathers every list in one pass")
    func branchSnapshotAggregates() async throws {
        guard hasGit() else { return }
        let workspace = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let repo = try makeRepoWithRemote(in: workspace)
        try runGit(["fetch", "origin"], at: repo)

        let snapshot = await GitWorktree.loadBranchSnapshot(at: repo)
        #expect(snapshot.local.contains("main"))
        #expect(snapshot.remote.contains("origin/main"))
        #expect(snapshot.inUse.contains("main"))
        #expect(snapshot.hasRemotes)
        #expect(snapshot.lastFetch != nil)
    }

    @Test("the snapshot skips remote work entirely for a repo with no remote")
    func branchSnapshotSkipsRemoteWorkWithoutRemotes() async throws {
        guard hasGit() else { return }
        let workspace = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let repo = workspace.appendingPathComponent("plain", isDirectory: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        try runGit(["init", "-b", "main"], at: repo)
        try runGit(["commit", "--allow-empty", "-m", "initial"], at: repo, withIdentity: true)

        let snapshot = await GitWorktree.loadBranchSnapshot(at: repo)
        #expect(snapshot.local == ["main"])
        #expect(snapshot.remote.isEmpty)
        #expect(snapshot.hasRemotes == false)
        #expect(snapshot.lastFetch == nil)
    }

    @Test("checkoutRemoteWorktree creates a tracking branch, not a detached HEAD")
    func checkoutRemoteWorktreeTracks() throws {
        guard hasGit() else { return }
        let workspace = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let repo = try makeRepoWithRemote(in: workspace)
        try runGit(["branch", "feature/theirs"], at: repo)
        try runGit(["push", "origin", "feature/theirs"], at: repo)
        try runGit(["branch", "-D", "feature/theirs"], at: repo)
        #expect(!GitWorktree.listLocalBranches(at: repo).contains("feature/theirs"))

        let worktreePath = workspace.appendingPathComponent("theirs", isDirectory: true)
        let result = GitWorktree.checkoutRemoteWorktree(
            remoteRef: "origin/feature/theirs",
            localBranch: "feature/theirs",
            newPath: worktreePath,
            sourceRepoPath: repo
        )
        guard case .success = result else {
            Issue.record("checkoutRemoteWorktree failed: \(result)")
            return
        }
        let head = try runGitCapturing(["rev-parse", "--abbrev-ref", "HEAD"], at: worktreePath)
        #expect(head == "feature/theirs")
        let upstream = try runGitCapturing(["rev-parse", "--abbrev-ref", "@{u}"], at: worktreePath)
        #expect(upstream == "origin/feature/theirs")
    }

    // MARK: - Status

    @Test("status reports the branch, its divergence and dirty files")
    func statusReportsDivergence() throws {
        guard hasGit() else { return }
        let workspace = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let repo = try makeRepoWithRemote(in: workspace)
        try runGit(["commit", "--allow-empty", "-m", "local work"], at: repo, withIdentity: true)
        try "scratch\n".write(
            to: repo.appendingPathComponent("notes.txt"),
            atomically: true,
            encoding: .utf8
        )

        guard case .status(let status) = GitWorktree.status(at: repo) else {
            Issue.record("status came back unavailable")
            return
        }
        #expect(status.branch == "main")
        #expect(status.comparisonRef == "origin/main")
        #expect(status.ahead == 1)
        #expect(status.behind == 0)
        #expect(status.changedFiles == 1)
    }

    @Test("a base branch gives divergence numbers where an upstream would give none")
    func statusComparesAgainstRecordedBase() throws {
        guard hasGit() else { return }
        let workspace = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let sourceRepo = workspace.appendingPathComponent("source", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceRepo, withIntermediateDirectories: true)
        try runGit(["init", "-b", "main"], at: sourceRepo)
        try runGit(["commit", "--allow-empty", "-m", "initial"], at: sourceRepo, withIdentity: true)

        let worktreePath = workspace.appendingPathComponent("twin", isDirectory: true)
        let added = GitWorktree.addWorktree(
            newBranch: "feature/twin",
            newPath: worktreePath,
            base: "main",
            sourceRepoPath: sourceRepo
        )
        guard case .success = added else {
            Issue.record("addWorktree failed: \(added)")
            return
        }
        try runGit(["commit", "--allow-empty", "-m", "work"], at: worktreePath, withIdentity: true)
        try runGit(["commit", "--allow-empty", "-m", "more work"], at: worktreePath, withIdentity: true)
        try runGit(["commit", "--allow-empty", "-m", "meanwhile"], at: sourceRepo, withIdentity: true)

        guard case .status(let bare) = GitWorktree.status(at: worktreePath) else {
            Issue.record("status came back unavailable")
            return
        }
        #expect(bare.comparisonRef == nil)
        #expect(bare.ahead == 0)
        #expect(bare.behind == 0)

        guard case .status(let based) = GitWorktree.status(at: worktreePath, base: "main") else {
            Issue.record("status came back unavailable")
            return
        }
        #expect(based.comparisonRef == "main")
        #expect(based.ahead == 2)
        #expect(based.behind == 1)
    }

    @Test("a base branch that no longer exists falls back instead of erroring")
    func statusFallsBackWhenBaseIsGone() throws {
        guard hasGit() else { return }
        let workspace = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let repo = try makeRepoWithRemote(in: workspace)
        try runGit(["commit", "--allow-empty", "-m", "local work"], at: repo, withIdentity: true)

        guard case .status(let status) = GitWorktree.status(at: repo, base: "deleted-base") else {
            Issue.record("status came back unavailable")
            return
        }
        #expect(status.comparisonRef == "origin/main")
        #expect(status.ahead == 1)
    }

    @Test("status is unavailable for a directory that isn't a working tree")
    func statusUnavailableOutsideRepo() throws {
        guard hasGit() else { return }
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(GitWorktree.status(at: dir) == .unavailable)
    }

    // MARK: - Helpers

    private func makeRepoWithRemote(in workspace: URL) throws -> URL {
        let remote = workspace.appendingPathComponent("origin.git", isDirectory: true)
        try FileManager.default.createDirectory(at: remote, withIntermediateDirectories: true)
        try runGit(["init", "--bare", "-b", "main"], at: remote)

        let repo = workspace.appendingPathComponent("source", isDirectory: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        try runGit(["init", "-b", "main"], at: repo)
        try runGit(["commit", "--allow-empty", "-m", "initial"], at: repo, withIdentity: true)
        try runGit(["remote", "add", "origin", remote.path], at: repo)
        try runGit(["push", "-u", "origin", "main"], at: repo)
        return repo
    }

    private func hasGit() -> Bool {
        CommandResolver.resolve("git") != nil
    }

    private struct GitNotInstalled: Error {}

    private func makeTempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitWorktreeTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

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

    private func runGitCapturing(_ args: [String], at cwd: URL) throws -> String {
        guard let git = CommandResolver.resolve("git") else { throw GitNotInstalled() }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: git)
        task.arguments = args
        task.currentDirectoryURL = cwd
        let stdout = Pipe()
        task.standardOutput = stdout
        task.standardError = Pipe()
        try task.run()
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        return (String(data: data, encoding: .utf8) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private struct GitCommandFailed: Error, CustomStringConvertible {
        let args: [String]
        let stderr: String
        var description: String { "git \(args.joined(separator: " ")) failed: \(stderr)" }
    }
}
