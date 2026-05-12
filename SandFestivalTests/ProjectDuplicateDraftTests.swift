import Foundation
import Testing
@testable import SandFestival

@Suite("ProjectDuplicateDraft auto-derivation")
struct ProjectDuplicateDraftTests {

    @Test("initial draft seeds name with source name and path with parent dir")
    func initialDraftDefaults() {
        let draft = makeDraft(sourcePath: "/Users/me/repo", sourceName: "Demo")
        #expect(draft.name == "Demo")
        #expect(draft.branchName == "")
        #expect(draft.pathString == "/Users/me")
        #expect(draft.baseBranch == nil)
    }

    @Test("typing a branch updates derived name and path")
    func branchChangeFlowsToDerivedFields() {
        var draft = makeDraft(sourcePath: "/Users/me/repo", sourceName: "Demo")
        draft.branchName = "new-feature"
        draft.refreshDerivedFields()
        #expect(draft.name == "Demo (new-feature)")
        #expect(draft.pathString == "/Users/me/new-feature")
    }

    @Test("clearing the branch reverts derived fields when user hasn't edited them")
    func clearingBranchRevertsDerivedFields() {
        var draft = makeDraft(sourcePath: "/Users/me/repo", sourceName: "Demo")
        draft.branchName = "new-feature"
        draft.refreshDerivedFields()
        draft.branchName = ""
        draft.refreshDerivedFields()
        #expect(draft.name == "Demo")
        #expect(draft.pathString == "/Users/me")
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
        #expect(draft.pathString == "/Users/me/other-feature")
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
        #expect(draft.pathString == "/Users/me/spaced")
    }

    @Test("autoStart carries over from the source project")
    func autoStartInheritsFromSource() {
        let source = Project(
            name: "Demo",
            path: URL(fileURLWithPath: "/Users/me/repo"),
            autoStart: true
        )
        let draft = ProjectDuplicateDraft(source: source, availableBranches: [])
        #expect(draft.autoStart == true)
    }

    // MARK: - Helpers

    private func makeDraft(sourcePath: String, sourceName: String) -> ProjectDuplicateDraft {
        let source = Project(name: sourceName, path: URL(fileURLWithPath: sourcePath))
        return ProjectDuplicateDraft(source: source, availableBranches: [])
    }
}
