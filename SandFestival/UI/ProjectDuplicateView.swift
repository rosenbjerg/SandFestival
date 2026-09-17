import AppKit
import SwiftUI

struct ProjectDuplicateView: View {
    let source: Project
    let onCreate: (Project) -> Void
    let onCancel: () -> Void

    @State private var draft: ProjectDuplicateDraft
    @State private var isCreating = false
    @State private var errorMessage: String?
    @State private var isFetching = false
    @State private var fetchError: String?

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

    // Refresh even on failure: a multi-remote fetch can update refs and still exit non-zero.
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

    private var branchBinding: Binding<String> {
        Binding(
            get: { draft.branchName },
            set: { newValue in
                draft.branchName = newValue.replacingOccurrences(of: " ", with: "-")
                draft.refreshDerivedFields()
            }
        )
    }

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

    private var createWorktreeBinding: Binding<Bool> {
        Binding(
            get: { draft.createWorktree },
            set: { newValue in
                draft.createWorktree = newValue
                draft.refreshDerivedFields()
            }
        )
    }

    private var modeBinding: Binding<WorktreeMode> {
        Binding(
            get: { draft.worktreeMode },
            set: { newValue in
                guard newValue != draft.worktreeMode else { return }
                draft.worktreeMode = newValue
                draft.branchName = ""
                // The remembered default, not nil: a round trip through
                // Existing branch must not drop the user's usual base.
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

    private func isNono(_ command: String) -> Bool {
        (command as NSString).lastPathComponent == "nono"
    }

    private func submit() {
        let snapshot = draft
        let trimmedName = snapshot.name.trimmingCharacters(in: .whitespaces)

        errorMessage = nil

        guard snapshot.createWorktree else {
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
        let localBranch = snapshot.resolvedLocalBranch
        let isRemote = snapshot.isRemoteSelection
        let resolvedPath = snapshot.resolvedPathString
        let base = snapshot.baseBranch?.trimmingCharacters(in: .whitespaces)

        isCreating = true

        let sourceRepoPath = source.path
        let newPath = URL(fileURLWithPath: resolvedPath)

        let worktreesDir = sourceRepoPath.appendingPathComponent(".worktrees").path + "/"
        let shouldUpdateGitignore = newPath.path.hasPrefix(worktreesDir)

        let mode = snapshot.worktreeMode
        let recordedBase = mode == .newBranch ? base.flatMap { $0.isEmpty ? nil : $0 } : nil

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
                    if mode == .newBranch {
                        baseBranchStore.remember(base, for: snapshot.resolvedParentProjectID)
                    }
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
                            branch: localBranch,
                            baseBranch: recordedBase
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

enum WorktreeMode: Hashable {
    case newBranch
    case existingBranch
}

enum DuplicateBlockingIssue: Equatable {
    case nameEmpty
    case branchEmpty
    case pathEmpty
    case branchNameInvalid
    case branchAlreadyExists(branch: String)
    case branchNotLocal
    case branchInUse
    case pathOccupied

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
    // The top-level ancestor, never source.id: the sidebar renders two levels,
    // so a grandchild would have no row.
    let resolvedParentProjectID: UUID
    let rememberedBaseBranch: String?
    var availableBranches: [String]
    var remoteBranches: [String]
    var branchesInUse: Set<String>
    var hasRemotes: Bool
    var lastFetch: Date?
    let isGitRepo: Bool
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
        let parent = source.path.appendingPathComponent(".worktrees").path
        let resolvedIsGitRepo = isGitRepo ?? GitWorktree.isGitRepo(at: source.path)
        let resolvedIsGitInstalled = isGitInstalled ?? GitWorktree.isGitInstalled()
        let lineageID = source.parentProjectID ?? source.id
        let remembered = (baseBranchStore ?? WorktreeBaseBranchStore()).base(for: lineageID)
        self.sourceName = source.name
        self.parentDir = parent
        self.sourcePath = source.path
        self.resolvedParentProjectID = lineageID
        self.rememberedBaseBranch = remembered
        self.availableBranches = availableBranches ?? []
        self.remoteBranches = remoteBranches ?? []
        self.branchesInUse = branchesInUse ?? []
        self.hasRemotes = hasRemotes ?? false
        self.isGitRepo = resolvedIsGitRepo
        self.isGitInstalled = resolvedIsGitInstalled
        self.name = source.name
        self.branchName = ""
        self.baseBranch = remembered
        self.pathString = parent
        self.autoStart = source.autoStart
        // Off when the section is hidden: a hidden-but-on toggle would still gate validity.
        self.createWorktree = resolvedIsGitRepo && resolvedIsGitInstalled
        self.worktreeMode = .newBranch
    }

    var isValid: Bool { blockingIssue == nil }

    // Not deduped against locals, unlike checkoutRefs: `main` and `origin/main`
    // are different commits, and the remote one is the point when local is behind.
    var baseRefs: [GitRef] {
        availableBranches.map { GitRef(name: $0, kind: .local) }
            + remoteBranches.map { GitRef(name: $0, kind: .remote) }
    }

    // Deduped, unlike baseRefs: a remote pick creates a local tracking branch
    // by short name, which git refuses when that name is already taken.
    var checkoutRefs: [GitRef] {
        let locals = Set(availableBranches)
        return availableBranches.map { GitRef(name: $0, kind: .local) }
            + remoteBranches
                .filter { !locals.contains(GitWorktree.localName(forRemoteRef: $0)) }
                .map { GitRef(name: $0, kind: .remote) }
    }

    var isRemoteSelection: Bool {
        guard worktreeMode == .existingBranch else { return false }
        return remoteBranches.contains(branchName.trimmingCharacters(in: .whitespaces))
    }

    var resolvedLocalBranch: String {
        let trimmed = branchName.trimmingCharacters(in: .whitespaces)
        guard isRemoteSelection else { return trimmed }
        return GitWorktree.localName(forRemoteRef: trimmed)
    }

    var blockingIssue: DuplicateBlockingIssue? {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return .nameEmpty }
        guard createWorktree else { return nil }
        let trimmedBranch = branchName.trimmingCharacters(in: .whitespaces)
        guard !trimmedBranch.isEmpty else { return .branchEmpty }
        guard !pathString.trimmingCharacters(in: .whitespaces).isEmpty else { return .pathEmpty }
        switch worktreeMode {
        case .newBranch:
            guard GitWorktree.isValidBranchName(trimmedBranch) else { return .branchNameInvalid }
            if availableBranches.contains(trimmedBranch) {
                return .branchAlreadyExists(branch: trimmedBranch)
            }
        case .existingBranch:
            if remoteBranches.contains(trimmedBranch) {
                let local = GitWorktree.localName(forRemoteRef: trimmedBranch)
                if availableBranches.contains(local) {
                    return .branchAlreadyExists(branch: local)
                }
            } else {
                guard availableBranches.contains(trimmedBranch) else { return .branchNotLocal }
                guard !branchesInUse.contains(trimmedBranch) else { return .branchInUse }
            }
        }
        if pathIsOccupied { return .pathOccupied }
        return nil
    }

    // Not a bare fileExists: git reuses an empty directory, so only a file or
    // a non-empty directory blocks.
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

    mutating func pruneUnknownBaseBranch() {
        // An empty list means the listing failed or hasn't landed, not that the branch is gone.
        guard !availableBranches.isEmpty, let base = baseBranch else { return }
        guard !availableBranches.contains(base), !remoteBranches.contains(base) else { return }
        baseBranch = nil
    }

    // URL(fileURLWithPath:) doesn't expand `~`; without this we'd create a directory named "~".
    var resolvedPathString: String {
        let trimmed = pathString.trimmingCharacters(in: .whitespaces)
        return (trimmed as NSString).expandingTildeInPath
    }

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

    // From the path, not the branch: a `/` in a branch name comes back from
    // the panel as `:`.
    var suggestedDirName: String {
        let leaf = (resolvedPathString as NSString).lastPathComponent
        return leaf.isEmpty ? sourceName : leaf
    }

    // NSSavePanel silently ignores a directoryURL that doesn't exist, and
    // `.worktrees/` usually doesn't yet.
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
