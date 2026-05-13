import SwiftUI

/// Confirmation sheet shown when removing a project that was created via
/// "Duplicate…". Lets the user pick whether to also `git worktree remove`
/// the worktree directory, optionally `git branch -d|-D` the branch the
/// worktree was tracking, and whether to force both past their safety
/// checks.
struct ProjectRemovalView: View {
    let project: Project
    let onRemove: () -> Void
    let onClose: () -> Void

    @State private var removeWorktree: Bool = false
    @State private var deleteBranch: Bool = false
    @State private var force: Bool = false
    @State private var isWorking: Bool = false
    @State private var errorMessage: String?
    /// True once `git worktree remove` succeeded. Used to flip the sheet
    /// into a "partial-failure acknowledgement" state when the worktree
    /// went away but the follow-up `git branch -d` failed — the user
    /// can't meaningfully retry (the worktree is already gone), so we
    /// just keep the error visible and let them confirm dismissal.
    @State private var partialFailureAfterRemoval: Bool = false

    private var hasBranch: Bool {
        guard let info = project.worktreeInfo else { return false }
        return !info.branch.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(String(format: String(localized: "removal.title"), project.name))
                .font(.headline)

            if let info = project.worktreeInfo {
                Text(String(format: String(localized: "removal.body"), info.branch, project.path.path))
                    .fixedSize(horizontal: false, vertical: true)

                Toggle(isOn: $removeWorktree) {
                    Text(String(format: String(localized: "removal.option.remove_worktree"), project.path.path))
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
                .onChange(of: removeWorktree) { _, newValue in
                    // You can't `git branch -d` a branch that's currently
                    // checked out in a worktree, so the branch toggle only
                    // makes sense when the worktree is being removed too.
                    if !newValue { deleteBranch = false }
                }

                if hasBranch {
                    Toggle(isOn: $deleteBranch) {
                        Text(String(format: String(localized: "removal.option.delete_branch"), info.branch))
                            .lineLimit(2)
                            .truncationMode(.middle)
                    }
                    .padding(.leading, 18)
                    .disabled(!removeWorktree)
                }

                Toggle(String(localized: "removal.option.force"), isOn: $force)
                    .padding(.leading, 18)
                    .disabled(!removeWorktree && !deleteBranch)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                if isWorking {
                    ProgressView().controlSize(.small)
                }
                Spacer()
                if partialFailureAfterRemoval {
                    Button(String(localized: "removal.action.acknowledge")) {
                        onRemove()
                        onClose()
                    }
                    .keyboardShortcut(.defaultAction)
                } else {
                    Button(String(localized: "removal.action.cancel"), role: .cancel) {
                        onClose()
                    }
                    .keyboardShortcut(.cancelAction)
                    .disabled(isWorking)
                    Button(String(localized: "removal.action.confirm"), role: .destructive, action: confirm)
                        .keyboardShortcut(.defaultAction)
                        .disabled(isWorking)
                }
            }
        }
        .padding(20)
        .frame(minWidth: 460)
    }

    private func confirm() {
        guard removeWorktree, let info = project.worktreeInfo else {
            onRemove()
            onClose()
            return
        }

        let worktreePath = project.path
        let sourceRepoPath = info.sourceRepoPath
        let branch = info.branch.trimmingCharacters(in: .whitespaces)
        let alsoDeleteBranch = deleteBranch && !branch.isEmpty
        let useForce = force
        errorMessage = nil
        isWorking = true

        Task {
            let outcome = await Task.detached { () -> RemovalOutcome in
                let removal = GitWorktree.removeWorktree(
                    worktreePath: worktreePath,
                    sourceRepoPath: sourceRepoPath,
                    force: useForce
                )
                guard case .success = removal else {
                    return .worktreeFailed(removal)
                }
                guard alsoDeleteBranch else {
                    return .bothSucceeded
                }
                let branchResult = GitWorktree.deleteBranch(
                    name: branch,
                    sourceRepoPath: sourceRepoPath,
                    force: useForce
                )
                switch branchResult {
                case .success:
                    return .bothSucceeded
                case .failure(let err):
                    return .branchFailedAfterRemoval(err)
                }
            }.value

            await MainActor.run {
                isWorking = false
                switch outcome {
                case .bothSucceeded:
                    onRemove()
                    onClose()
                case .worktreeFailed(let result):
                    if case .failure(let err) = result {
                        errorMessage = err.errorDescription
                    }
                case .branchFailedAfterRemoval(let err):
                    // Worktree is gone, but the branch survived. Surface
                    // the branch-delete error so the user knows what
                    // failed, and switch the sheet to a single
                    // acknowledgement button — they can't retry from
                    // here without recreating the worktree.
                    errorMessage = String(
                        format: String(localized: "removal.error.branch_after_removal"),
                        err.errorDescription ?? ""
                    )
                    partialFailureAfterRemoval = true
                }
            }
        }
    }

    private enum RemovalOutcome {
        case bothSucceeded
        case worktreeFailed(Result<Void, GitWorktreeError>)
        case branchFailedAfterRemoval(GitWorktreeError)
    }
}
