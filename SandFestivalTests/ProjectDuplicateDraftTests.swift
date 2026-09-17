import Foundation
import Testing
@testable import SandFestival

@Suite("ProjectDuplicateDraft auto-derivation")
struct ProjectDuplicateDraftTests {

    @Test("initial draft seeds name with source name and path with .worktrees dir")
    func initialDraftDefaults() {
        let draft = makeDraft(sourcePath: "/Users/me/repo", sourceName: "Demo")
        #expect(draft.name == "Demo")
        #expect(draft.branchName == "")
        #expect(draft.pathString == "/Users/me/repo/.worktrees")
        #expect(draft.baseBranch == nil)
    }

    @Test("typing a branch updates derived name and path")
    func branchChangeFlowsToDerivedFields() {
        var draft = makeDraft(sourcePath: "/Users/me/repo", sourceName: "Demo")
        draft.branchName = "new-feature"
        draft.refreshDerivedFields()
        #expect(draft.name == "Demo (new-feature)")
        #expect(draft.pathString == "/Users/me/repo/.worktrees/new-feature")
    }

    @Test("clearing the branch reverts derived fields when user hasn't edited them")
    func clearingBranchRevertsDerivedFields() {
        var draft = makeDraft(sourcePath: "/Users/me/repo", sourceName: "Demo")
        draft.branchName = "new-feature"
        draft.refreshDerivedFields()
        draft.branchName = ""
        draft.refreshDerivedFields()
        #expect(draft.name == "Demo")
        #expect(draft.pathString == "/Users/me/repo/.worktrees")
    }

    @Test("manually editing the name pins it — later branch changes don't clobber it")
    func userEditedNameStopsTracking() {
        var draft = makeDraft(sourcePath: "/Users/me/repo", sourceName: "Demo")
        draft.branchName = "new-feature"
        draft.refreshDerivedFields()
        draft.name = "My Custom Name"
        draft.nameUserEdited = true
        draft.branchName = "other-feature"
        draft.refreshDerivedFields()
        #expect(draft.name == "My Custom Name")
        #expect(draft.pathString == "/Users/me/repo/.worktrees/other-feature")
    }

    @Test("manually editing the path pins it — later branch changes don't clobber it")
    func userEditedPathStopsTracking() {
        var draft = makeDraft(sourcePath: "/Users/me/repo", sourceName: "Demo")
        draft.branchName = "new-feature"
        draft.refreshDerivedFields()
        draft.pathString = "/elsewhere/custom-dir"
        draft.pathUserEdited = true
        draft.branchName = "other-feature"
        draft.refreshDerivedFields()
        #expect(draft.pathString == "/elsewhere/custom-dir")
        #expect(draft.name == "Demo (other-feature)")
    }

    @Test("isValid requires a non-blank branch, name, and path")
    func validationRules() {
        var draft = makeDraft(sourcePath: "/Users/me/repo", sourceName: "Demo")
        #expect(!draft.isValid)
        draft.branchName = "feat"
        draft.refreshDerivedFields()
        #expect(draft.isValid)
        draft.branchName = "   "
        #expect(!draft.isValid)
    }

    @Test("whitespace in the branch name doesn't leak into the derived suffix")
    func branchWhitespaceIsTrimmed() {
        var draft = makeDraft(sourcePath: "/Users/me/repo", sourceName: "Demo")
        draft.branchName = "  spaced  "
        draft.refreshDerivedFields()
        #expect(draft.name == "Demo (spaced)")
        #expect(draft.pathString == "/Users/me/repo/.worktrees/spaced")
    }

    @Test("autoStart carries over from the source project")
    func autoStartInheritsFromSource() {
        let source = Project(
            name: "Demo",
            path: URL(fileURLWithPath: "/Users/me/repo"),
            autoStart: true
        )
        let draft = ProjectDuplicateDraft(
            source: source,
            availableBranches: [],
            isGitRepo: true,
            isGitInstalled: true
        )
        #expect(draft.autoStart == true)
    }

    @Test("non-git sources default to createWorktree == false")
    func nonGitDefaultsOffWorktree() {
        let source = Project(name: "Demo", path: URL(fileURLWithPath: "/Users/me/notes"))
        let draft = ProjectDuplicateDraft(
            source: source,
            availableBranches: [],
            isGitRepo: false,
            isGitInstalled: true
        )
        #expect(draft.createWorktree == false)
        #expect(draft.isGitRepo == false)
    }

    @Test("missing git binary defaults createWorktree off even on a git repo")
    func missingGitDefaultsOffWorktree() {
        let source = Project(name: "Demo", path: URL(fileURLWithPath: "/Users/me/repo"))
        let draft = ProjectDuplicateDraft(
            source: source,
            availableBranches: [],
            isGitRepo: true,
            isGitInstalled: false
        )
        #expect(draft.isGitRepo == true)
        #expect(draft.isGitInstalled == false)
        #expect(draft.createWorktree == false)
        #expect(draft.isValid)
    }

    @Test("isValid for a no-worktree duplicate only requires a name")
    func noWorktreeValidationOnlyNeedsName() {
        var draft = makeDraft(sourcePath: "/Users/me/notes", sourceName: "Notes", isGitRepo: false)
        #expect(draft.isValid)
        draft.name = "   "
        draft.nameUserEdited = true
        #expect(!draft.isValid)
        draft.name = "Notes (copy)"
        #expect(draft.isValid)
    }

    @Test("resolvedPathString expands a leading tilde to the user's home")
    func resolvedPathExpandsTilde() {
        var draft = makeDraft(sourcePath: "/Users/me/repo", sourceName: "Demo")
        draft.pathString = "~/elsewhere/twin"
        draft.pathUserEdited = true
        let expected = (("~/elsewhere/twin") as NSString).expandingTildeInPath
        #expect(draft.resolvedPathString == expected)
        // Guards against an environment where `~` doesn't expand, which would
        // let a regression through silently.
        #expect(!draft.resolvedPathString.hasPrefix("~"))
    }

    @Test("resolvedPathString trims whitespace before expanding")
    func resolvedPathTrimsWhitespace() {
        var draft = makeDraft(sourcePath: "/Users/me/repo", sourceName: "Demo")
        draft.pathString = "   /tmp/twin   "
        draft.pathUserEdited = true
        #expect(draft.resolvedPathString == "/tmp/twin")
    }

    @Test("resolvedPathString leaves non-tilde absolute paths unchanged")
    func resolvedPathLeavesAbsolutePathsAlone() {
        var draft = makeDraft(sourcePath: "/Users/me/repo", sourceName: "Demo")
        draft.pathString = "/elsewhere/twin"
        draft.pathUserEdited = true
        #expect(draft.resolvedPathString == "/elsewhere/twin")
    }

    @Test("turning createWorktree off resets the auto-derived name back to the source name")
    func togglingWorktreeOffRevertsTrackingName() {
        var draft = makeDraft(sourcePath: "/Users/me/repo", sourceName: "Demo", isGitRepo: true)
        draft.branchName = "new-feature"
        draft.refreshDerivedFields()
        #expect(draft.name == "Demo (new-feature)")
        draft.createWorktree = false
        draft.refreshDerivedFields()
        #expect(draft.name == "Demo")
    }

    @Test("default worktree mode is newBranch")
    func defaultModeIsNewBranch() {
        let draft = makeDraft(sourcePath: "/Users/me/repo", sourceName: "Demo")
        #expect(draft.worktreeMode == .newBranch)
    }

    @Test("existing-branch mode requires the branch to be in availableBranches")
    func existingModeValidityChecksMembership() {
        var draft = makeDraft(
            sourcePath: "/Users/me/repo",
            sourceName: "Demo",
            availableBranches: ["main", "feature-x"]
        )
        draft.worktreeMode = .existingBranch
        draft.branchName = "feature-x"
        draft.refreshDerivedFields()
        #expect(draft.isValid)

        draft.branchName = "ghost-branch"
        draft.refreshDerivedFields()
        #expect(!draft.isValid)
    }

    @Test("existing-branch mode rejects branches already checked out elsewhere")
    func existingModeRejectsInUseBranches() {
        var draft = makeDraft(
            sourcePath: "/Users/me/repo",
            sourceName: "Demo",
            availableBranches: ["main", "feature-x"],
            branchesInUse: ["main"]
        )
        draft.worktreeMode = .existingBranch
        draft.branchName = "main"
        draft.refreshDerivedFields()
        #expect(!draft.isValid)
        draft.branchName = "feature-x"
        draft.refreshDerivedFields()
        #expect(draft.isValid)
    }

    @Test("new-branch mode ignores availableBranches membership")
    func newModeAllowsArbitraryBranchName() {
        var draft = makeDraft(
            sourcePath: "/Users/me/repo",
            sourceName: "Demo",
            availableBranches: ["main"],
            branchesInUse: ["main"]
        )
        draft.worktreeMode = .newBranch
        draft.branchName = "brand-new"
        draft.refreshDerivedFields()
        #expect(draft.isValid)
    }

    @Test("picking an existing branch derives name and path the same way new-branch does")
    func existingBranchDerivesFields() {
        var draft = makeDraft(
            sourcePath: "/Users/me/repo",
            sourceName: "Demo",
            availableBranches: ["main", "feature-x"]
        )
        draft.worktreeMode = .existingBranch
        draft.branchName = "feature-x"
        draft.refreshDerivedFields()
        #expect(draft.name == "Demo (feature-x)")
        #expect(draft.pathString == "/Users/me/repo/.worktrees/feature-x")
    }

    @Test("duplicating a top-level project anchors the child to that project")
    func resolvedParentAnchorsToTopLevelSource() {
        let source = Project(name: "Demo", path: URL(fileURLWithPath: "/Users/me/repo"))
        let draft = ProjectDuplicateDraft(source: source, isGitRepo: true, isGitInstalled: true)
        #expect(draft.resolvedParentProjectID == source.id)
    }

    @Test("duplicating a duplicate anchors the new child to the top-level ancestor")
    func resolvedParentAnchorsToAncestorNotChild() {
        let topLevelID = UUID()
        let childSource = Project(
            name: "Demo (feature-x)",
            path: URL(fileURLWithPath: "/Users/me/repo/.worktrees/feature-x"),
            parentProjectID: topLevelID
        )
        let draft = ProjectDuplicateDraft(source: childSource, isGitRepo: true, isGitInstalled: true)
        #expect(draft.resolvedParentProjectID == topLevelID)
        #expect(draft.resolvedParentProjectID != childSource.id)
    }

    // MARK: - Pre-flight validation

    @Test("new-branch mode blocks an invalid branch name")
    func newBranchModeRejectsInvalidName() {
        var draft = makeDraft(sourcePath: "/Users/me/repo", sourceName: "Demo")
        draft.branchName = "bad branch name"
        draft.refreshDerivedFields()
        #expect(draft.blockingIssue == .branchNameInvalid)
        #expect(!draft.isValid)
    }

    @Test("new-branch mode blocks a branch name that already exists")
    func newBranchModeRejectsExistingBranch() {
        var draft = makeDraft(
            sourcePath: "/Users/me/repo",
            sourceName: "Demo",
            availableBranches: ["main", "feature-x"]
        )
        draft.branchName = "feature-x"
        draft.refreshDerivedFields()
        #expect(draft.blockingIssue == .branchAlreadyExists(branch: "feature-x"))
        #expect(!draft.isValid)
    }

    @Test("existing-branch mode blocks a branch checked out elsewhere")
    func existingModeBlockingIssueForInUseBranch() {
        var draft = makeDraft(
            sourcePath: "/Users/me/repo",
            sourceName: "Demo",
            availableBranches: ["main"],
            branchesInUse: ["main"]
        )
        draft.worktreeMode = .existingBranch
        draft.branchName = "main"
        draft.refreshDerivedFields()
        #expect(draft.blockingIssue == .branchInUse)
    }

    @Test("a non-empty target path blocks submission; an empty directory doesn't")
    func occupiedPathBlocksSubmission() throws {
        let fileManager = FileManager.default
        let occupied = fileManager.temporaryDirectory
            .appendingPathComponent("dup-occupied-\(UUID())", isDirectory: true)
        try fileManager.createDirectory(at: occupied, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: occupied) }
        try "x".write(
            to: occupied.appendingPathComponent("file.txt"),
            atomically: true,
            encoding: .utf8
        )

        var draft = makeDraft(sourcePath: "/Users/me/repo", sourceName: "Demo")
        draft.branchName = "new-feature"
        draft.refreshDerivedFields()
        draft.pathString = occupied.path
        draft.pathUserEdited = true
        #expect(draft.blockingIssue == .pathOccupied)
        #expect(!draft.isValid)

        let empty = fileManager.temporaryDirectory
            .appendingPathComponent("dup-empty-\(UUID())", isDirectory: true)
        try fileManager.createDirectory(at: empty, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: empty) }
        draft.pathString = empty.path
        #expect(draft.blockingIssue == nil)
        #expect(draft.isValid)
    }

    // MARK: - Remembered base branch

    @Test("a remembered base branch pre-selects the base field")
    func rememberedBaseSeedsDraft() {
        let source = Project(name: "Demo", path: URL(fileURLWithPath: "/Users/me/repo"))
        let store = makeStore()
        store.remember("main", for: source.id)

        let draft = ProjectDuplicateDraft(
            source: source,
            baseBranchStore: store,
            isGitRepo: true,
            isGitInstalled: true
        )
        #expect(draft.baseBranch == "main")
        #expect(draft.rememberedBaseBranch == "main")
    }

    @Test("a worktree child reads the base remembered against its top-level ancestor")
    func rememberedBaseSharedAcrossLineage() {
        let topLevelID = UUID()
        let store = makeStore()
        store.remember("main", for: topLevelID)

        let child = Project(
            name: "Demo (feature-x)",
            path: URL(fileURLWithPath: "/Users/me/repo/.worktrees/feature-x"),
            parentProjectID: topLevelID
        )
        let draft = ProjectDuplicateDraft(
            source: child,
            baseBranchStore: store,
            isGitRepo: true,
            isGitInstalled: true
        )
        #expect(draft.baseBranch == "main")
    }

    @Test("nothing remembered leaves the base at the Current HEAD sentinel")
    func noMemoryLeavesBaseNil() {
        let source = Project(name: "Demo", path: URL(fileURLWithPath: "/Users/me/repo"))
        let draft = ProjectDuplicateDraft(
            source: source,
            baseBranchStore: makeStore(),
            isGitRepo: true,
            isGitInstalled: true
        )
        #expect(draft.baseBranch == nil)
        #expect(draft.rememberedBaseBranch == nil)
    }

    @Test("pruning drops a remembered base the repo no longer has")
    func pruneDropsDeletedBase() {
        let source = Project(name: "Demo", path: URL(fileURLWithPath: "/Users/me/repo"))
        let store = makeStore()
        store.remember("gone", for: source.id)

        var draft = ProjectDuplicateDraft(
            source: source,
            baseBranchStore: store,
            isGitRepo: true,
            isGitInstalled: true
        )
        #expect(draft.baseBranch == "gone")
        draft.availableBranches = ["main", "develop"]
        draft.pruneUnknownBaseBranch()
        #expect(draft.baseBranch == nil)
        #expect(draft.rememberedBaseBranch == "gone")
    }

    @Test("pruning keeps a remembered base that still exists")
    func pruneKeepsLiveBase() {
        let source = Project(name: "Demo", path: URL(fileURLWithPath: "/Users/me/repo"))
        let store = makeStore()
        store.remember("main", for: source.id)

        var draft = ProjectDuplicateDraft(
            source: source,
            baseBranchStore: store,
            isGitRepo: true,
            isGitInstalled: true
        )
        draft.availableBranches = ["main", "develop"]
        draft.pruneUnknownBaseBranch()
        #expect(draft.baseBranch == "main")
    }

    @Test("pruning against an empty branch list is a no-op")
    func pruneNoOpsWhileBranchesUnknown() {
        let source = Project(name: "Demo", path: URL(fileURLWithPath: "/Users/me/repo"))
        let store = makeStore()
        store.remember("main", for: source.id)

        var draft = ProjectDuplicateDraft(
            source: source,
            baseBranchStore: store,
            isGitRepo: true,
            isGitInstalled: true
        )
        draft.pruneUnknownBaseBranch()
        #expect(draft.baseBranch == "main")
    }

    // MARK: - Branch picker filter

    @Test("the branch filter matches case-insensitive substrings")
    func branchFilterMatching() {
        let refs = ["main", "develop", "feature/Login", "feature/signup", "hotfix/crash"]
            .map { GitRef(name: $0, kind: .local) }
        func names(_ matched: [GitRef]) -> [String] { matched.map(\.name) }
        #expect(BranchPickerField.matching(refs, filter: "") == refs)
        #expect(BranchPickerField.matching(refs, filter: "   ") == refs)
        #expect(names(BranchPickerField.matching(refs, filter: "feature")) == ["feature/Login", "feature/signup"])
        #expect(names(BranchPickerField.matching(refs, filter: "LOGIN")) == ["feature/Login"])
        #expect(BranchPickerField.matching(refs, filter: "ghost").isEmpty)
    }

    @Test("the filter spans both sections and keeps each ref's kind")
    func branchFilterSpansRemotes() {
        let refs = [GitRef(name: "main", kind: .local), GitRef(name: "origin/main", kind: .remote)]
        let matched = BranchPickerField.matching(refs, filter: "main")
        #expect(matched == refs)
        #expect(BranchPickerField.matching(refs, filter: "origin") == [refs[1]])
    }

    // MARK: - Remote refs

    @Test("base refs offer local and remote branches without deduping them")
    func baseRefsKeepBothSides() {
        var draft = makeDraft(
            sourcePath: "/Users/me/repo",
            sourceName: "Demo",
            availableBranches: ["main", "feature-x"]
        )
        draft.remoteBranches = ["origin/main", "origin/release"]
        #expect(draft.baseRefs == [
            GitRef(name: "main", kind: .local),
            GitRef(name: "feature-x", kind: .local),
            GitRef(name: "origin/main", kind: .remote),
            GitRef(name: "origin/release", kind: .remote),
        ])
    }

    @Test("a remembered remote base survives the prune")
    func pruneKeepsRemoteBase() {
        var draft = makeDraft(
            sourcePath: "/Users/me/repo",
            sourceName: "Demo",
            availableBranches: ["main"]
        )
        draft.remoteBranches = ["origin/main"]
        draft.baseBranch = "origin/main"
        draft.pruneUnknownBaseBranch()
        #expect(draft.baseBranch == "origin/main")
    }

    @Test("a base branch missing from both lists is pruned")
    func pruneDropsBaseMissingFromBothLists() {
        var draft = makeDraft(
            sourcePath: "/Users/me/repo",
            sourceName: "Demo",
            availableBranches: ["main"]
        )
        draft.remoteBranches = ["origin/main"]
        draft.baseBranch = "origin/deleted"
        draft.pruneUnknownBaseBranch()
        #expect(draft.baseBranch == nil)
    }

    @Test("checkout refs drop remotes whose short name is already local")
    func checkoutRefsDedupeAgainstLocals() {
        var draft = makeDraft(
            sourcePath: "/Users/me/repo",
            sourceName: "Demo",
            availableBranches: ["main", "feature-x"]
        )
        draft.remoteBranches = ["origin/main", "origin/feature-x", "origin/theirs"]
        #expect(draft.checkoutRefs == [
            GitRef(name: "main", kind: .local),
            GitRef(name: "feature-x", kind: .local),
            GitRef(name: "origin/theirs", kind: .remote),
        ])
    }

    @Test("a remote pick resolves to the tracking branch it will create")
    func remotePickResolvesToLocalBranch() {
        var draft = makeDraft(
            sourcePath: "/Users/me/repo",
            sourceName: "Demo",
            availableBranches: ["main"]
        )
        draft.remoteBranches = ["origin/feat/foo"]
        draft.worktreeMode = .existingBranch
        draft.branchName = "origin/feat/foo"
        #expect(draft.isRemoteSelection)
        #expect(draft.resolvedLocalBranch == "feat/foo")
        draft.refreshDerivedFields()
        #expect(draft.name == "Demo (feat/foo)")
        #expect(draft.pathString == "/Users/me/repo/.worktrees/feat/foo")
    }

    @Test("a local pick is not mistaken for a remote one")
    func localPickIsNotTreatedAsRemote() {
        var draft = makeDraft(
            sourcePath: "/Users/me/repo",
            sourceName: "Demo",
            availableBranches: ["main"]
        )
        draft.remoteBranches = ["origin/main"]
        draft.worktreeMode = .existingBranch
        draft.branchName = "main"
        #expect(draft.isRemoteSelection == false)
        #expect(draft.resolvedLocalBranch == "main")
    }

    @Test("new-branch mode never reads its typed name as a remote ref")
    func newBranchModeIgnoresRemoteMembership() {
        var draft = makeDraft(
            sourcePath: "/Users/me/repo",
            sourceName: "Demo",
            availableBranches: ["main"]
        )
        draft.remoteBranches = ["origin/feat"]
        draft.branchName = "origin/feat"
        #expect(draft.isRemoteSelection == false)
        #expect(draft.resolvedLocalBranch == "origin/feat")
    }

    @Test("a remote pick validates unless its local name is taken")
    func remotePickValidation() {
        var draft = makeDraft(
            sourcePath: "/Users/me/repo",
            sourceName: "Demo",
            availableBranches: ["main"]
        )
        draft.remoteBranches = ["origin/theirs"]
        draft.worktreeMode = .existingBranch
        draft.branchName = "origin/theirs"
        draft.refreshDerivedFields()
        #expect(draft.blockingIssue == nil)

        draft.availableBranches = ["main", "theirs"]
        #expect(draft.blockingIssue == .branchAlreadyExists(branch: "theirs"))
    }

    // MARK: - Save panel suggestions

    @Test("the save panel is named after the path leaf, not a slashed branch")
    func suggestedDirNameUsesPathLeaf() {
        var draft = makeDraft(sourcePath: "/Users/me/repo", sourceName: "Demo")
        draft.branchName = "feat/foo"
        draft.refreshDerivedFields()
        #expect(draft.pathString == "/Users/me/repo/.worktrees/feat/foo")
        #expect(draft.suggestedDirName == "foo")
    }

    @Test("the save panel follows a path the user typed rather than the branch")
    func suggestedDirNameFollowsUserEditedPath() {
        var draft = makeDraft(sourcePath: "/Users/me/repo", sourceName: "Demo")
        draft.branchName = "feat-x"
        draft.refreshDerivedFields()
        draft.pathString = "/Users/me/elsewhere/custom-dir"
        draft.pathUserEdited = true
        #expect(draft.suggestedDirName == "custom-dir")
    }

    @Test("a blank path falls the save panel name back to the source name")
    func suggestedDirNameFallsBackToSourceName() {
        var draft = makeDraft(sourcePath: "/Users/me/repo", sourceName: "Demo")
        draft.pathString = "   "
        draft.pathUserEdited = true
        #expect(draft.suggestedDirName == "Demo")
    }

    @Test("the save panel opens at the deepest ancestor that exists")
    func suggestedParentDirWalksUpToExistingAncestor() throws {
        let base = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("sandfestival-duplicate-draft-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }

        var draft = makeDraft(sourcePath: base.path, sourceName: "Demo")
        draft.branchName = "feat/foo"
        draft.refreshDerivedFields()
        #expect(draft.suggestedParentDir == (base.path as NSString).standardizingPath)
    }

    // MARK: - Helpers

    private func makeDraft(
        sourcePath: String,
        sourceName: String,
        isGitRepo: Bool = true,
        isGitInstalled: Bool = true,
        availableBranches: [String] = [],
        branchesInUse: Set<String> = []
    ) -> ProjectDuplicateDraft {
        let source = Project(name: sourceName, path: URL(fileURLWithPath: sourcePath))
        return ProjectDuplicateDraft(
            source: source,
            baseBranchStore: makeStore(),
            availableBranches: availableBranches,
            branchesInUse: branchesInUse,
            isGitRepo: isGitRepo,
            isGitInstalled: isGitInstalled
        )
    }

    private func makeStore() -> WorktreeBaseBranchStore {
        let name = "app.sandfestival.tests.duplicate-draft.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return WorktreeBaseBranchStore(defaults: defaults)
    }
}
