import AppKit
import SwiftUI

/// Sheet that creates a sibling `Project`. By default the new project is
/// backed by a fresh `git worktree`, but the user can opt out — in that
/// case the duplicate shares the source's path and only differs in name /
/// auto-start. Either way the new project records `parentProjectID` so
/// the sidebar can render it grouped underneath its source.
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

                if draft.isGitRepo {
                    Section(String(localized: "duplicate.section.worktree")) {
                        Toggle(String(localized: "duplicate.field.create_worktree"), isOn: createWorktreeBinding)
                        if draft.createWorktree {
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
        .frame(minWidth: 540, minHeight: 360)
        .navigationTitle(String(localized: "duplicate.title"))
        .task {
            guard draft.isGitRepo, draft.availableBranches.isEmpty else { return }
            let branches = await GitWorktree.listLocalBranchesAsync(at: source.path)
            draft.availableBranches = branches
        }
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

    // Toggling "Create git worktree" off should leave the name field in a
    // sensible state. Tracking-mode names like "Demo (feature-x)" stop
    // making sense when we're no longer making a feature-x branch, so we
    // reset the auto-derived name back to the source name. A name the user
    // explicitly typed is left alone.
    private var createWorktreeBinding: Binding<Bool> {
        Binding(
            get: { draft.createWorktree },
            set: { newValue in
                draft.createWorktree = newValue
                draft.refreshDerivedFields()
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
        let trimmedName = snapshot.name.trimmingCharacters(in: .whitespaces)

        errorMessage = nil

        guard snapshot.createWorktree else {
            // No-worktree duplicate: share the source path, no git work.
            let project = Project(
                name: trimmedName,
                path: source.path,
                agentID: source.agentID,
                command: source.command,
                args: source.args,
                env: source.env,
                autoStart: snapshot.autoStart,
                worktreeInfo: nil,
                parentProjectID: source.id
            )
            onCreate(project)
            return
        }

        let trimmedBranch = snapshot.branchName.trimmingCharacters(in: .whitespaces)
        let trimmedPath = snapshot.pathString.trimmingCharacters(in: .whitespaces)
        let base = snapshot.baseBranch?.trimmingCharacters(in: .whitespaces)

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
                        ),
                        parentProjectID: source.id
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
struct ProjectDuplicateDraft {
    var name: String
    var branchName: String
    var baseBranch: String?
    var pathString: String
    var autoStart: Bool
    var createWorktree: Bool
    var nameUserEdited: Bool = false
    var pathUserEdited: Bool = false

    let sourceName: String
    let parentDir: String
    let sourcePath: URL
    /// Populated asynchronously by the view's `.task` so sheet construction
    /// doesn't block on a `git branch` subprocess on the main thread — same
    /// pattern as `ProjectEditorView`'s `discoveredProfiles`.
    var availableBranches: [String]
    let isGitRepo: Bool

    init(
        source: Project,
        availableBranches: [String]? = nil,
        isGitRepo: Bool? = nil
    ) {
        let parent = source.path.deletingLastPathComponent().path
        // Tests inject overrides to avoid shelling out to git.
        let resolvedIsGitRepo = isGitRepo ?? GitWorktree.isGitRepo(at: source.path)
        self.sourceName = source.name
        self.parentDir = parent
        self.sourcePath = source.path
        // Branches start empty; the view's `.task` swaps them in once the
        // off-main-thread subprocess returns.
        self.availableBranches = availableBranches ?? []
        self.isGitRepo = resolvedIsGitRepo
        self.name = source.name
        self.branchName = ""
        self.baseBranch = nil
        self.pathString = parent
        self.autoStart = source.autoStart
        // Default to "make a worktree" when we can — that's the path users
        // following the duplicate flow usually want. Non-git sources don't
        // get the toggle at all, so this just stays false there.
        self.createWorktree = resolvedIsGitRepo
    }

    var isValid: Bool {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        guard createWorktree else { return true }
        return !branchName.trimmingCharacters(in: .whitespaces).isEmpty &&
            !pathString.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Auto-fills `name` and `pathString` from the current branch name, but
    /// only for fields the user hasn't typed into yet. Once a field has been
    /// edited it stops tracking, so the branch field can be tweaked
    /// afterwards without clobbering custom values. When `createWorktree` is
    /// off the branch is irrelevant — fall back to the source name / parent
    /// dir for the auto-derived fields.
    mutating func refreshDerivedFields() {
        let trimmed = branchName.trimmingCharacters(in: .whitespaces)
        let effectiveBranch = createWorktree ? trimmed : ""
        if !nameUserEdited {
            name = effectiveBranch.isEmpty ? sourceName : "\(sourceName) (\(effectiveBranch))"
        }
        if !pathUserEdited {
            let dir = effectiveBranch.isEmpty ? "" : "/\(effectiveBranch)"
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
