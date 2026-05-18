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

                if draft.isGitRepo && draft.isGitInstalled {
                    Section(String(localized: "duplicate.section.worktree")) {
                        Toggle(String(localized: "duplicate.field.create_worktree"), isOn: createWorktreeBinding)
                        if draft.createWorktree {
                            Picker(String(localized: "duplicate.field.mode"), selection: modeBinding) {
                                Text(String(localized: "duplicate.field.mode.new"))
                                    .tag(WorktreeMode.newBranch)
                                Text(String(localized: "duplicate.field.mode.existing"))
                                    .tag(WorktreeMode.existingBranch)
                            }
                            .pickerStyle(.segmented)
                            if draft.worktreeMode == .newBranch {
                                TextField(String(localized: "duplicate.field.branch"), text: branchBinding)
                                basePicker
                            } else {
                                existingBranchPicker
                            }
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
            guard draft.isGitRepo, draft.isGitInstalled, draft.availableBranches.isEmpty else { return }
            async let branches = GitWorktree.listLocalBranchesAsync(at: source.path)
            async let inUse = GitWorktree.listInUseBranchesAsync(at: source.path)
            let (resolvedBranches, resolvedInUse) = await (branches, inUse)
            draft.availableBranches = resolvedBranches
            draft.branchesInUse = resolvedInUse
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

    // Existing-branch picker. Branches checked out in another worktree show
    // up in the menu with a "(in use)" suffix and are disabled — git would
    // refuse them, and we want to make that obvious before the user submits.
    // While the async branch list is still loading we surface a "Loading…"
    // hint inside the picker label rather than an empty disabled control.
    @ViewBuilder
    private var existingBranchPicker: some View {
        let trimmed = draft.branchName.trimmingCharacters(in: .whitespaces)
        let menuLabel: String = {
            if !trimmed.isEmpty { return trimmed }
            if draft.availableBranches.isEmpty {
                return String(localized: "duplicate.field.existing_branch.loading")
            }
            return String(localized: "duplicate.field.existing_branch.placeholder")
        }()
        LabeledContent(String(localized: "duplicate.field.existing_branch")) {
            Menu {
                ForEach(draft.availableBranches, id: \.self) { branch in
                    let inUse = draft.branchesInUse.contains(branch)
                    Button {
                        draft.branchName = branch
                        draft.refreshDerivedFields()
                    } label: {
                        if inUse {
                            Text(String(format: String(localized: "duplicate.field.existing_branch.in_use"), branch))
                        } else {
                            Text(branch)
                        }
                    }
                    .disabled(inUse)
                }
            } label: {
                Text(menuLabel)
                    .foregroundStyle(trimmed.isEmpty ? .secondary : .primary)
            }
            .disabled(draft.availableBranches.isEmpty)
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

    // The branch field means different things in each mode (text to create
    // vs. branch to check out), so clear it when the user flips modes —
    // otherwise typing "feat-x" then switching to "Existing branch" leaves a
    // value that doesn't match any local branch and disables the confirm
    // button without explanation.
    private var modeBinding: Binding<WorktreeMode> {
        Binding(
            get: { draft.worktreeMode },
            set: { newValue in
                guard newValue != draft.worktreeMode else { return }
                draft.worktreeMode = newValue
                draft.branchName = ""
                draft.baseBranch = nil
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
        let resolvedPath = snapshot.resolvedPathString
        let base = snapshot.baseBranch?.trimmingCharacters(in: .whitespaces)

        isCreating = true

        let sourceRepoPath = source.path
        let newPath = URL(fileURLWithPath: resolvedPath)

        // Only manage the gitignore when the worktree lands inside the
        // source repo's default `.worktrees/` directory. If the user
        // pointed it elsewhere (a sibling dir, a totally separate path)
        // we don't know what pattern to ignore, and guessing would pollute
        // their gitignore.
        let worktreesDir = sourceRepoPath.appendingPathComponent(".worktrees").path + "/"
        let shouldUpdateGitignore = newPath.path.hasPrefix(worktreesDir)

        let mode = snapshot.worktreeMode

        Task {
            let result = await Task.detached {
                let outcome: Result<Void, GitWorktreeError>
                switch mode {
                case .newBranch:
                    outcome = GitWorktree.addWorktree(
                        newBranch: trimmedBranch,
                        newPath: newPath,
                        base: base,
                        sourceRepoPath: sourceRepoPath
                    )
                case .existingBranch:
                    outcome = GitWorktree.checkoutWorktree(
                        existingBranch: trimmedBranch,
                        newPath: newPath,
                        sourceRepoPath: sourceRepoPath
                    )
                }
                if case .success = outcome, shouldUpdateGitignore {
                    GitWorktree.ensureWorktreesIgnored(at: sourceRepoPath)
                }
                return outcome
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

/// Which side of the worktree section the user is interacting with: creating
/// a brand-new branch or checking out one that already exists in the repo.
enum WorktreeMode: Hashable {
    case newBranch
    case existingBranch
}

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
    var worktreeMode: WorktreeMode
    var nameUserEdited: Bool = false
    var pathUserEdited: Bool = false

    let sourceName: String
    let parentDir: String
    let sourcePath: URL
    /// Populated asynchronously by the view's `.task` so sheet construction
    /// doesn't block on a `git branch` subprocess on the main thread — same
    /// pattern as `ProjectEditorView`'s `discoveredProfiles`.
    var availableBranches: [String]
    /// Branches currently checked out in another worktree (incl. the source's
    /// own HEAD). Shown disabled in the existing-branch picker because
    /// `git worktree add <path> <branch>` refuses them.
    var branchesInUse: Set<String>
    let isGitRepo: Bool
    /// Whether a `git` binary is on PATH. The Worktree section hides itself
    /// when this is false even if `isGitRepo` is true — there'd be no way
    /// to act on it. Kept separate from `isGitRepo` so tests can exercise
    /// each gate independently.
    let isGitInstalled: Bool

    init(
        source: Project,
        availableBranches: [String]? = nil,
        branchesInUse: Set<String>? = nil,
        isGitRepo: Bool? = nil,
        isGitInstalled: Bool? = nil
    ) {
        // Default to `<source>/.worktrees/<branch>` — matches the
        // convention most worktree tooling (Cursor, recent VSCode
        // extensions, etc.) defaults to, and keeps each repo's worktrees
        // grouped under the repo itself rather than scattering them
        // across the source's parent directory. Users still get a path
        // field they can edit if they want a different location.
        let parent = source.path.appendingPathComponent(".worktrees").path
        // Tests inject overrides to avoid shelling out to git.
        let resolvedIsGitRepo = isGitRepo ?? GitWorktree.isGitRepo(at: source.path)
        let resolvedIsGitInstalled = isGitInstalled ?? GitWorktree.isGitInstalled()
        self.sourceName = source.name
        self.parentDir = parent
        self.sourcePath = source.path
        // Branches start empty; the view's `.task` swaps them in once the
        // off-main-thread subprocess returns.
        self.availableBranches = availableBranches ?? []
        self.branchesInUse = branchesInUse ?? []
        self.isGitRepo = resolvedIsGitRepo
        self.isGitInstalled = resolvedIsGitInstalled
        self.name = source.name
        self.branchName = ""
        self.baseBranch = nil
        self.pathString = parent
        self.autoStart = source.autoStart
        // Default to "make a worktree" when we can — that's the path users
        // following the duplicate flow usually want. Sources where the
        // section won't even be shown (non-git, or git missing entirely)
        // start with the toggle off so a hidden-but-defaulted-on flag can't
        // affect validity.
        self.createWorktree = resolvedIsGitRepo && resolvedIsGitInstalled
        self.worktreeMode = .newBranch
    }

    var isValid: Bool {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        guard createWorktree else { return true }
        let trimmedBranch = branchName.trimmingCharacters(in: .whitespaces)
        let trimmedPath = pathString.trimmingCharacters(in: .whitespaces)
        guard !trimmedBranch.isEmpty, !trimmedPath.isEmpty else { return false }
        // Existing-branch mode also requires that the selected branch is
        // actually one of the local branches and isn't currently checked out
        // somewhere else — otherwise `git worktree add` would just fail.
        if worktreeMode == .existingBranch {
            guard availableBranches.contains(trimmedBranch) else { return false }
            guard !branchesInUse.contains(trimmedBranch) else { return false }
        }
        return true
    }

    /// The path the user typed, trimmed and tilde-expanded. The text
    /// field accepts shell-style paths like `~/code/foo` because that's
    /// what people type into a path field — but `URL(fileURLWithPath:)`
    /// doesn't expand `~`, so we'd otherwise create a directory literally
    /// named `~`. Run expansion once here so both the URL we pass to
    /// `git worktree add` and the prefix check against the source's
    /// `.worktrees/` directory see the resolved path.
    var resolvedPathString: String {
        let trimmed = pathString.trimmingCharacters(in: .whitespaces)
        return (trimmed as NSString).expandingTildeInPath
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
