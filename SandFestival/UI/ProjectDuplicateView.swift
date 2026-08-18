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
    @State private var isFetching = false
    @State private var fetchError: String?

    /// Seeds the base-branch field on open and is written back on a successful
    /// create, so the next duplicate in this lineage defaults to the same base.
    private let baseBranchStore: WorktreeBaseBranchStore

    init(source: Project, onCreate: @escaping (Project) -> Void, onCancel: @escaping () -> Void) {
        let store = WorktreeBaseBranchStore()
        self.source = source
        self.onCreate = onCreate
        self.onCancel = onCancel
        self.baseBranchStore = store
        _draft = State(initialValue: ProjectDuplicateDraft(source: source, baseBranchStore: store))
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
                                BranchPickerField(
                                    label: String(localized: "duplicate.field.existing_branch"),
                                    refs: draft.checkoutRefs,
                                    inUse: draft.branchesInUse,
                                    empty: .placeholder(
                                        text: String(localized: "duplicate.field.existing_branch.placeholder"),
                                        loading: String(localized: "duplicate.field.existing_branch.loading")
                                    ),
                                    selection: existingBranchBinding
                                )
                            }
                            if draft.hasRemotes {
                                fetchRow
                            }
                            HStack {
                                TextField(String(localized: "duplicate.field.worktree_path"), text: pathBinding)
                                    .truncationMode(.head)
                                Button(String(localized: "duplicate.field.worktree_path.choose")) {
                                    choosePath()
                                }
                            }
                            if let hint = draft.blockingIssue?.inlineMessage {
                                Label(hint, systemImage: "exclamationmark.triangle")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
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
            apply(await GitWorktree.loadBranchSnapshot(at: source.path))
        }
    }

    @ViewBuilder
    private var basePicker: some View {
        BranchPickerField(
            label: String(localized: "duplicate.field.base_branch"),
            refs: draft.baseRefs,
            empty: .sentinel(label: String(localized: "duplicate.field.base_branch.current")),
            selection: $draft.baseBranch
        )
    }

    @ViewBuilder
    private var fetchRow: some View {
        HStack(spacing: 8) {
            Button(String(localized: "duplicate.field.fetch"), action: fetch)
                .disabled(isFetching)
            if isFetching {
                ProgressView().controlSize(.small)
            }
            if let fetchError {
                Text(fetchError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .textSelection(.enabled)
            } else {
                Text(lastFetchCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var lastFetchCaption: String {
        guard let date = draft.lastFetch else {
            return String(localized: "duplicate.field.fetch.never")
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return String(
            format: String(localized: "duplicate.field.fetch.last"),
            formatter.localizedString(for: date, relativeTo: Date())
        )
    }

    /// Refreshes the branch lists even when the fetch itself failed: a
    /// multi-remote fetch can update some refs and still exit non-zero, and
    /// the failure is reported alongside rather than instead of the result.
    private func fetch() {
        isFetching = true
        fetchError = nil
        let repoPath = source.path
        Task {
            let result = await Task.detached { GitWorktree.fetch(at: repoPath) }.value
            apply(await GitWorktree.loadBranchSnapshot(at: repoPath))
            isFetching = false
            if case .failure(let error) = result {
                fetchError = error.errorDescription
            }
        }
    }

    private func apply(_ snapshot: GitWorktree.BranchSnapshot) {
        draft.availableBranches = snapshot.local
        draft.remoteBranches = snapshot.remote
        draft.branchesInUse = snapshot.inUse
        draft.hasRemotes = snapshot.hasRemotes
        draft.lastFetch = snapshot.lastFetch
        draft.pruneUnknownBaseBranch()
    }

    // The name and path fields keep tracking the branch name until the user
    // edits them manually. These bindings flip the "user edited" flags when
    // the value diverges from the auto-derived default.
    private var branchBinding: Binding<String> {
        Binding(
            get: { draft.branchName },
            set: { newValue in
                // Spaces aren't valid in branch names; fold them to dashes as
                // the user types so the field never holds an invalid value.
                draft.branchName = newValue.replacingOccurrences(of: " ", with: "-")
                draft.refreshDerivedFields()
            }
        )
    }

    // The existing-branch picker models "no branch picked" as nil; bridge that
    // onto the draft's non-optional branchName. Picking still re-derives the
    // name and path fields, exactly like typing into the new-branch field.
    private var existingBranchBinding: Binding<String?> {
        Binding(
            get: { draft.branchName.isEmpty ? nil : draft.branchName },
            set: { newValue in
                draft.branchName = newValue ?? ""
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
    // button without explanation. The base branch resets to the remembered
    // default rather than to nil, so a round trip through Existing branch
    // doesn't quietly cost the user their usual base.
    private var modeBinding: Binding<WorktreeMode> {
        Binding(
            get: { draft.worktreeMode },
            set: { newValue in
                guard newValue != draft.worktreeMode else { return }
                draft.worktreeMode = newValue
                draft.branchName = ""
                draft.baseBranch = draft.rememberedBaseBranch
                draft.pruneUnknownBaseBranch()
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

    /// Whether `command` resolves to the nono sandbox wrapper, so the
    /// `--allow <repo>` grant only gets injected into args nono understands.
    /// Matches on the basename so a full path like `/usr/local/bin/nono`
    /// still counts.
    private func isNono(_ command: String) -> Bool {
        (command as NSString).lastPathComponent == "nono"
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
                parentProjectID: snapshot.resolvedParentProjectID
            )
            onCreate(project)
            return
        }

        let trimmedBranch = snapshot.branchName.trimmingCharacters(in: .whitespaces)
        // The branch the project ends up on: identical to `trimmedBranch`
        // everywhere except a remote pick, where `origin/feat` becomes the
        // tracking branch `feat`.
        let localBranch = snapshot.resolvedLocalBranch
        let isRemote = snapshot.isRemoteSelection
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
                case .existingBranch where isRemote:
                    outcome = GitWorktree.checkoutRemoteWorktree(
                        remoteRef: trimmedBranch,
                        localBranch: localBranch,
                        newPath: newPath,
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
                    // Remember the base for next time — only in new-branch
                    // mode, where it was actually used. Checking out an
                    // existing branch takes no base, so it mustn't clobber
                    // the stored default.
                    if mode == .newBranch {
                        baseBranchStore.remember(base, for: snapshot.resolvedParentProjectID)
                    }
                    // The worktree's `.git` is a gitlink into the source
                    // repo's `.git/worktrees/…`, so the sandbox needs the
                    // source repo root granted or every git command 401s with
                    // "operation not permitted". Only meaningful for the nono
                    // wrapper — leave a custom command's args untouched.
                    let args = isNono(source.command)
                        ? NonoWorktreeArgs.grantingRepoAccess(
                            repoPath: sourceRepoPath.path,
                            in: source.args
                        )
                        : source.args
                    let project = Project(
                        name: trimmedName,
                        path: newPath,
                        agentID: source.agentID,
                        command: source.command,
                        args: args,
                        env: source.env,
                        autoStart: snapshot.autoStart,
                        worktreeInfo: WorktreeInfo(
                            sourceRepoPath: sourceRepoPath,
                            branch: localBranch
                        ),
                        parentProjectID: snapshot.resolvedParentProjectID
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

/// The first reason the duplicate sheet can't be submitted — used both to
/// gate the Confirm button and to explain *why* it's disabled. Catches the
/// cases that would otherwise only surface as a raw `git` error at submit.
enum DuplicateBlockingIssue: Equatable {
    case nameEmpty
    case branchEmpty
    case pathEmpty
    case branchNameInvalid
    case branchAlreadyExists(branch: String)
    case branchNotLocal
    case branchInUse
    case pathOccupied

    /// A user-facing explanation, or `nil` for issues self-evident from a
    /// blank field — no point captioning an empty box with "Branch is
    /// required".
    var inlineMessage: String? {
        switch self {
        case .nameEmpty, .branchEmpty, .pathEmpty:
            return nil
        case .branchNameInvalid:
            return String(localized: "duplicate.issue.branch_name_invalid")
        case .branchAlreadyExists(let branch):
            return String(format: String(localized: "duplicate.issue.branch_exists"), branch)
        case .branchNotLocal:
            return String(localized: "duplicate.issue.branch_not_local")
        case .branchInUse:
            return String(localized: "duplicate.issue.branch_in_use")
        case .pathOccupied:
            return String(localized: "duplicate.issue.path_occupied")
        }
    }
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
    /// The `parentProjectID` to stamp on the duplicate. The sidebar renders
    /// only two levels (top-level rows, then one pass of their children), so
    /// a duplicate whose parent is itself a child would render nowhere —
    /// orphaned in `projects.json` with no row. Anchoring every duplicate of
    /// a lineage to the top-level ancestor keeps them visible as siblings
    /// under that ancestor.
    ///
    /// Doubles as the key `WorktreeBaseBranchStore` remembers the base branch
    /// under, so a parent and all its worktree children share one memory.
    let resolvedParentProjectID: UUID
    /// The base branch remembered from the last worktree created in this
    /// lineage, or `nil` when there's nothing remembered. Seeds `baseBranch`
    /// and is restored when the user flips modes back to New branch.
    let rememberedBaseBranch: String?
    /// Populated asynchronously by the view's `.task` so sheet construction
    /// doesn't block on a `git branch` subprocess on the main thread — same
    /// pattern as `ProjectEditorView`'s `discoveredProfiles`.
    var availableBranches: [String]
    /// Remote-tracking branches (`origin/main`), carrying their remote prefix.
    var remoteBranches: [String]
    /// Branches currently checked out in another worktree (incl. the source's
    /// own HEAD). Shown disabled in the existing-branch picker because
    /// `git worktree add <path> <branch>` refuses them.
    var branchesInUse: Set<String>
    /// Whether the repo has any remote configured at all. Gates the fetch
    /// row: an empty `remoteBranches` means either "no remotes" or "never
    /// fetched", and only the second is worth offering a Fetch button for.
    var hasRemotes: Bool
    /// Mtime of `FETCH_HEAD`, for captioning how stale `remoteBranches` is.
    var lastFetch: Date?
    let isGitRepo: Bool
    /// Whether a `git` binary is on PATH. The Worktree section hides itself
    /// when this is false even if `isGitRepo` is true — there'd be no way
    /// to act on it. Kept separate from `isGitRepo` so tests can exercise
    /// each gate independently.
    let isGitInstalled: Bool

    init(
        source: Project,
        baseBranchStore: WorktreeBaseBranchStore? = nil,
        availableBranches: [String]? = nil,
        remoteBranches: [String]? = nil,
        branchesInUse: Set<String>? = nil,
        hasRemotes: Bool? = nil,
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
        let lineageID = source.parentProjectID ?? source.id
        let remembered = (baseBranchStore ?? WorktreeBaseBranchStore()).base(for: lineageID)
        self.sourceName = source.name
        self.parentDir = parent
        self.sourcePath = source.path
        self.resolvedParentProjectID = lineageID
        self.rememberedBaseBranch = remembered
        // Branches start empty; the view's `.task` swaps them in once the
        // off-main-thread subprocess returns.
        self.availableBranches = availableBranches ?? []
        self.remoteBranches = remoteBranches ?? []
        self.branchesInUse = branchesInUse ?? []
        self.hasRemotes = hasRemotes ?? false
        self.isGitRepo = resolvedIsGitRepo
        self.isGitInstalled = resolvedIsGitInstalled
        self.name = source.name
        self.branchName = ""
        // Pre-selected before the branch list has loaded, so the field shows
        // the remembered base immediately instead of flickering through
        // "Current HEAD". `pruneUnknownBaseBranch()` drops it after the load
        // if the branch is gone.
        self.baseBranch = remembered
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

    var isValid: Bool { blockingIssue == nil }

    /// Refs offerable as the base for a new branch. Remotes are deliberately
    /// *not* deduped against locals here: `main` and `origin/main` are
    /// different commits, and reaching for the remote one is the whole point
    /// when the local branch has fallen behind.
    var baseRefs: [GitRef] {
        availableBranches.map { GitRef(name: $0, kind: .local) }
            + remoteBranches.map { GitRef(name: $0, kind: .remote) }
    }

    /// Refs offerable in existing-branch mode. Here remotes *are* deduped
    /// against locals: picking one creates a local tracking branch by the
    /// remote's short name, which git refuses when that name is taken — and
    /// the existing local branch is what the user wanted anyway.
    var checkoutRefs: [GitRef] {
        let locals = Set(availableBranches)
        return availableBranches.map { GitRef(name: $0, kind: .local) }
            + remoteBranches
                .filter { !locals.contains(GitWorktree.localName(forRemoteRef: $0)) }
                .map { GitRef(name: $0, kind: .remote) }
    }

    /// True when the branch field holds a remote-tracking ref. Recovered by
    /// membership rather than stored, exactly like `branchesInUse`, so there's
    /// no second copy of the picker's state to drift.
    var isRemoteSelection: Bool {
        guard worktreeMode == .existingBranch else { return false }
        return remoteBranches.contains(branchName.trimmingCharacters(in: .whitespaces))
    }

    /// The local branch this duplicate will end up on. A remote pick creates
    /// a tracking branch named after the remote's short name, so `origin/feat`
    /// resolves to `feat` — which is what the project name, the worktree path
    /// and `WorktreeInfo` all need to use.
    var resolvedLocalBranch: String {
        let trimmed = branchName.trimmingCharacters(in: .whitespaces)
        guard isRemoteSelection else { return trimmed }
        return GitWorktree.localName(forRemoteRef: trimmed)
    }

    /// The first problem that blocks submission, or `nil` when the form is
    /// ready. Catches the doomed cases — invalid branch name, a branch that
    /// already exists, an occupied target path — that would otherwise only
    /// surface as a raw `git` error after the user clicks Confirm. The path
    /// check stats the filesystem; one `stat` per keystroke is cheap and is
    /// what makes the collision visible up front.
    var blockingIssue: DuplicateBlockingIssue? {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return .nameEmpty }
        guard createWorktree else { return nil }
        let trimmedBranch = branchName.trimmingCharacters(in: .whitespaces)
        guard !trimmedBranch.isEmpty else { return .branchEmpty }
        guard !pathString.trimmingCharacters(in: .whitespaces).isEmpty else { return .pathEmpty }
        switch worktreeMode {
        case .newBranch:
            guard GitWorktree.isValidBranchName(trimmedBranch) else { return .branchNameInvalid }
            // `git worktree add -b` refuses a branch name that already exists.
            // `availableBranches` is empty while still loading — treat that as
            // "can't tell yet" and let git be the backstop.
            if availableBranches.contains(trimmedBranch) {
                return .branchAlreadyExists(branch: trimmedBranch)
            }
        case .existingBranch:
            if remoteBranches.contains(trimmedBranch) {
                // The picker hides remote refs whose short name is taken, but
                // a list that went stale while the sheet was open could still
                // offer one — and the tracking branch couldn't be created.
                let local = GitWorktree.localName(forRemoteRef: trimmedBranch)
                if availableBranches.contains(local) {
                    return .branchAlreadyExists(branch: local)
                }
            } else {
                // The branch must be a real local branch and not already
                // checked out elsewhere — otherwise `git worktree add` fails.
                guard availableBranches.contains(trimmedBranch) else { return .branchNotLocal }
                guard !branchesInUse.contains(trimmedBranch) else { return .branchInUse }
            }
        }
        if pathIsOccupied { return .pathOccupied }
        return nil
    }

    /// True when something already lives at the resolved worktree path that
    /// would make `git worktree add` fail. An existing *empty* directory is
    /// fine — git reuses it — so only a file or a non-empty directory counts.
    private var pathIsOccupied: Bool {
        let path = resolvedPathString
        guard !path.isEmpty else { return false }
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory) else { return false }
        guard isDirectory.boolValue else { return true }
        let contents = (try? fileManager.contentsOfDirectory(atPath: path)) ?? []
        return !contents.isEmpty
    }

    /// Clears a pre-selected base branch that turned out not to exist — a
    /// remembered branch that has since been deleted or renamed. Called once
    /// the async branch list lands, so the field falls back to the visible
    /// "Current HEAD" sentinel rather than letting `git worktree add` fail at
    /// submit. A still-empty branch list means the listing failed (or hasn't
    /// arrived), which is not evidence the branch is gone.
    mutating func pruneUnknownBaseBranch() {
        guard !availableBranches.isEmpty, let base = baseBranch else { return }
        guard !availableBranches.contains(base), !remoteBranches.contains(base) else { return }
        baseBranch = nil
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
        let effectiveBranch = createWorktree ? resolvedLocalBranch : ""
        if !nameUserEdited {
            name = effectiveBranch.isEmpty ? sourceName : "\(sourceName) (\(effectiveBranch))"
        }
        if !pathUserEdited {
            let dir = effectiveBranch.isEmpty ? "" : "/\(effectiveBranch)"
            pathString = parentDir + dir
        }
    }

    /// Name to prefill the save panel's name field with. Derived from the
    /// path the sheet currently targets, *not* from the branch: a branch
    /// like `feat/foo` targets `.worktrees/feat/foo`, and a `/` handed to
    /// the name field comes back as `feat:foo` — macOS forbids the
    /// separator in a filename.
    var suggestedDirName: String {
        let leaf = (resolvedPathString as NSString).lastPathComponent
        return leaf.isEmpty ? sourceName : leaf
    }

    /// Directory to open the save panel in: the deepest ancestor of the
    /// targeted path that actually exists. `NSSavePanel` silently ignores a
    /// `directoryURL` that isn't there — and the default target sits under
    /// `.worktrees/`, which git only creates during `worktree add` — so
    /// without the walk up the panel opens somewhere unrelated.
    var suggestedParentDir: String {
        let target = resolvedPathString
        let start = target.isEmpty
            ? parentDir
            : (target as NSString).deletingLastPathComponent
        return Self.deepestExistingDirectory(from: start)
    }

    private static func deepestExistingDirectory(from path: String) -> String {
        let fileManager = FileManager.default
        var candidate = (path as NSString).standardizingPath
        while !candidate.isEmpty, candidate != "/" {
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: candidate, isDirectory: &isDirectory),
               isDirectory.boolValue {
                return candidate
            }
            candidate = (candidate as NSString).deletingLastPathComponent
        }
        return "/"
    }
}
