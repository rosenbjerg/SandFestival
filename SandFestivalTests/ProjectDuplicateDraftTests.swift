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
        // User overrides the suggested name.
        draft.name = "My Custom Name"
        draft.nameUserEdited = true
        // Then keeps tweaking the branch.
        draft.branchName = "other-feature"
        draft.refreshDerivedFields()
        #expect(draft.name == "My Custom Name")
        // Path still tracks because the user didn't touch it.
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
        // Name still tracks.
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
        let draft = ProjectDuplicateDraft(source: source, availableBranches: [], isGitRepo: true)
        #expect(draft.autoStart == true)
    }

    @Test("non-git sources default to createWorktree == false")
    func nonGitDefaultsOffWorktree() {
        let source = Project(name: "Demo", path: URL(fileURLWithPath: "/Users/me/notes"))
        let draft = ProjectDuplicateDraft(source: source, availableBranches: [], isGitRepo: false)
        #expect(draft.createWorktree == false)
        #expect(draft.isGitRepo == false)
    }

    @Test("isValid for a no-worktree duplicate only requires a name")
    func noWorktreeValidationOnlyNeedsName() {
        var draft = makeDraft(sourcePath: "/Users/me/notes", sourceName: "Notes", isGitRepo: false)
        // Default name = source name, so a freshly-built no-worktree draft is already valid.
        #expect(draft.isValid)
        // Blank name invalidates it.
        draft.name = "   "
        draft.nameUserEdited = true
        #expect(!draft.isValid)
        // Branch and path are irrelevant in this mode — even with both
        // blank, a sensible name keeps us valid.
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
        // Sanity: the expansion actually changed something — guards against
        // a test environment where `~` doesn't expand (would let a regression
        // slip through silently).
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

        // A branch that isn't in the local-branch list shouldn't validate —
        // the picker wouldn't have offered it, and git would just fail.
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
        // New-branch mode is creating a fresh branch, so a name that isn't in
        // the existing list (or even one that collides with an in-use branch
        // name — git will be the one to complain) is still considered valid
        // from the draft's perspective.
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

    // MARK: - Helpers

    private func makeDraft(
        sourcePath: String,
        sourceName: String,
        isGitRepo: Bool = true,
        availableBranches: [String] = [],
        branchesInUse: Set<String> = []
    ) -> ProjectDuplicateDraft {
        let source = Project(name: sourceName, path: URL(fileURLWithPath: sourcePath))
        return ProjectDuplicateDraft(
            source: source,
            availableBranches: availableBranches,
            branchesInUse: branchesInUse,
            isGitRepo: isGitRepo
        )
    }
}
