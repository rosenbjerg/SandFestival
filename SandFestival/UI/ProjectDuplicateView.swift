import AppKit
import SwiftUI

/// Sheet that creates a sibling `Project` backed by a fresh git worktree.
/// Mirrors `ProjectEditorView`'s shape — Form + Cancel/Confirm buttons in a
/// footer — so the two sheets feel like siblings rather than two different
/// dialogs.
struct ProjectDuplicateView: View {
    let source: Project
    let onCreate: (Project) -> Void
    let onCancel: () -> Void

    @State private var draft: ProjectDuplicateDraft
    @State private var isCreating = false
    @State private var errorMessage: String?

    init(source: Project, onCreate: @escaping (Project) -> Void, onCancel: @escaping () -> Void) {
        self.source = source
        self.onCreate = onCreate
        self.onCancel = onCancel
        _draft = State(initialValue: ProjectDuplicateDraft(source: source))
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    LabeledContent(String(localized: "duplicate.field.source")) {
                        Text(source.name)
                            .foregroundStyle(.secondary)
                    }
                }

                Section(String(localized: "duplicate.section.worktree")) {
                    TextField(String(localized: "duplicate.field.branch"), text: branchBinding)
                    basePicker
                    HStack {
                        TextField(String(localized: "duplicate.field.worktree_path"), text: pathBinding)
                            .truncationMode(.head)
                        Button(String(localized: "duplicate.field.worktree_path.choose")) {
                            choosePath()
                        }
                    }
                }

                Section(String(localized: "duplicate.section.project")) {
                    TextField(String(localized: "duplicate.field.name"), text: nameBinding)
                    Toggle(String(localized: "duplicate.field.auto_start"), isOn: $draft.autoStart)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.callout)
                            .foregroundStyle(.red)
                            .textSelection(.enabled)
                    }
                }
            }
            .formStyle(.grouped)
            .disabled(isCreating)

            Divider()

            HStack(spacing: 8) {
                if isCreating {
                    ProgressView().controlSize(.small)
                    Text(String(localized: "duplicate.progress"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(String(localized: "duplicate.action.cancel"), role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                    .disabled(isCreating)
                Button(String(localized: "duplicate.action.confirm"), action: submit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!draft.isValid || isCreating)
            }
            .padding()
        }
        .frame(minWidth: 540, minHeight: 420)
        .navigationTitle(String(localized: "duplicate.title"))
    }

    @ViewBuilder
    private var basePicker: some View {
        Picker(String(localized: "duplicate.field.base_branch"), selection: $draft.baseBranch) {
            Text(String(localized: "duplicate.field.base_branch.current"))
                .tag(String?.none)
            ForEach(draft.availableBranches, id: \.self) { branch in
                Text(branch).tag(String?.some(branch))
            }
        }
    }

    // The name and path fields keep tracking the branch name until the user
    // edits them manually. These bindings flip the "user edited" flags when
    // the value diverges from the auto-derived default.
    private var branchBinding: Binding<String> {
        Binding(
            get: { draft.branchName },
            set: { newValue in
                draft.branchName = newValue
                draft.refreshDerivedFields()
            }
        )
    }

    private var nameBinding: Binding<String> {
        Binding(
            get: { draft.name },
            set: { newValue in
                draft.name = newValue
                draft.nameUserEdited = true
            }
        )
    }

    private var pathBinding: Binding<String> {
        Binding(
            get: { draft.pathString },
            set: { newValue in
                draft.pathString = newValue
                draft.pathUserEdited = true
            }
        )
    }

    private func choosePath() {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.title = String(localized: "duplicate.choose_path.title")
        panel.nameFieldLabel = String(localized: "duplicate.choose_path.name_label")
        panel.nameFieldStringValue = draft.suggestedDirName
        panel.directoryURL = URL(fileURLWithPath: draft.suggestedParentDir, isDirectory: true)
        if panel.runModal() == .OK, let url = panel.url {
            draft.pathString = url.path
            draft.pathUserEdited = true
        }
    }

    private func submit() {
        let snapshot = draft
        let trimmedBranch = snapshot.branchName.trimmingCharacters(in: .whitespaces)
        let trimmedPath = snapshot.pathString.trimmingCharacters(in: .whitespaces)
        let trimmedName = snapshot.name.trimmingCharacters(in: .whitespaces)
        let base = snapshot.baseBranch?.trimmingCharacters(in: .whitespaces)

        errorMessage = nil
        isCreating = true

        let sourceRepoPath = source.path
        let newPath = URL(fileURLWithPath: trimmedPath)

        Task {
            let result = await Task.detached {
                GitWorktree.addWorktree(
                    newBranch: trimmedBranch,
                    newPath: newPath,
                    base: base,
                    sourceRepoPath: sourceRepoPath
                )
            }.value

            await MainActor.run {
                isCreating = false
                switch result {
                case .success:
                    let project = Project(
                        name: trimmedName,
                        path: newPath,
                        agentID: source.agentID,
                        command: source.command,
                        args: source.args,
                        env: source.env,
                        autoStart: snapshot.autoStart,
                        worktreeInfo: WorktreeInfo(
                            sourceRepoPath: sourceRepoPath,
                            branch: trimmedBranch
                        )
                    )
                    onCreate(project)
                case .failure(let error):
                    errorMessage = error.errorDescription
                }
            }
        }
    }
}

// MARK: - Draft

/// View-model for `ProjectDuplicateView`. Lives at module scope (not
/// fileprivate) so the auto-derivation behavior can be unit-tested without
/// instantiating the SwiftUI view.
struct ProjectProjectDuplicateDraft {
    var name: String
    var branchName: String
    var baseBranch: String?
    var pathString: String
    var autoStart: Bool
    var nameUserEdited: Bool = false
    var pathUserEdited: Bool = false

    let sourceName: String
    let parentDir: String
    let availableBranches: [String]

    init(source: Project, availableBranches: [String]? = nil) {
        let parent = source.path.deletingLastPathComponent().path
        self.sourceName = source.name
        self.parentDir = parent
        // Tests inject an explicit branch list to avoid shelling out to git.
        self.availableBranches = availableBranches ?? GitWorktree.listLocalBranches(at: source.path)
        self.name = source.name
        self.branchName = ""
        self.baseBranch = nil
        self.pathString = parent
        self.autoStart = source.autoStart
    }

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !branchName.trimmingCharacters(in: .whitespaces).isEmpty &&
        !pathString.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Auto-fills `name` and `pathString` from the current branch name, but
    /// only for fields the user hasn't typed into yet. Once a field has been
    /// edited it stops tracking, so the branch field can be tweaked
    /// afterwards without clobbering custom values.
    mutating func refreshDerivedFields() {
        let trimmed = branchName.trimmingCharacters(in: .whitespaces)
        if !nameUserEdited {
            name = trimmed.isEmpty ? sourceName : "\(sourceName) (\(trimmed))"
        }
        if !pathUserEdited {
            let dir = trimmed.isEmpty ? "" : "/\(trimmed)"
            pathString = parentDir + dir
        }
    }

    var suggestedDirName: String {
        let trimmed = branchName.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? sourceName : trimmed
    }

    var suggestedParentDir: String {
        parentDir
    }
}
