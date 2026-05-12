import SwiftUI

/// Confirmation sheet shown when removing a project that was created via
/// "Duplicate…". Lets the user pick whether to also `git worktree remove`
/// the worktree directory, with an optional `--force` for dirty trees.
struct ProjectRemovalView: View {
    let project: Project
    let onRemove: () -> Void
    let onClose: () -> Void

    @State private var removeWorktree: Bool = false
    @State private var force: Bool = false
    @State private var isWorking: Bool = false
    @State private var errorMessage: String?

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

                Toggle(String(localized: "removal.option.force"), isOn: $force)
                    .padding(.leading, 18)
                    .disabled(!removeWorktree)
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
        let useForce = force
        errorMessage = nil
        isWorking = true

        Task {
            let result = await Task.detached {
                GitWorktree.removeWorktree(
                    worktreePath: worktreePath,
                    sourceRepoPath: sourceRepoPath,
                    force: useForce
                )
            }.value

            await MainActor.run {
                isWorking = false
                switch result {
                case .success:
                    onRemove()
                    onClose()
                case .failure(let err):
                    errorMessage = err.errorDescription
                }
            }
        }
    }
}
