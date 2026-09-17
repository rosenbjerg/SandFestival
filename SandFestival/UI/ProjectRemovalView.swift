import SwiftUI

struct ProjectRemovalView: View {
    let project: Project
    let onTerminate: () async -> Bool
    let onRemove: () -> Void
    let onClose: () -> Void

    @State private var removeWorktree: Bool = false
    @State private var deleteBranch: Bool = false
    @State private var force: Bool = false
    @State private var isWorking: Bool = false
    @State private var errorMessage: String?
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
                Text(String(format: String(localized: "removal.body"), info.branch, project.displayPath))
                    .fixedSize(horizontal: false, vertical: true)

                Toggle(isOn: $removeWorktree) {
                    Text(String(format: String(localized: "removal.option.remove_worktree"), project.displayPath))
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
                .onChange(of: removeWorktree) { _, newValue in
                    // git refuses to delete a branch still checked out in the worktree.
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
            // Confirmed dead, not merely signalled: git must not remove the
            // worktree under a live agent.
            guard await onTerminate() else {
                isWorking = false
                errorMessage = String(localized: "removal.error.session_still_running")
                return
            }

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
