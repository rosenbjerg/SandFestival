import AppKit
import SwiftUI

struct SidebarView: View {
    @Bindable var manager: SessionManager
    let statusStore: WorktreeStatusStore
    @Binding var editorTarget: ProjectEditorTarget?
    @Binding var duplicateTarget: Project?
    @Binding var removalTarget: Project?

    /// Persisted across launches as a comma-joined list of UUID strings.
    /// Parents default to expanded; this holds the ids the user folded up.
    @AppStorage("sidebar.collapsedParents") private var collapsedParentsStorage: String = ""
    @State private var query = ""

    private var collapsedParents: Set<Project.ID> {
        Set(collapsedParentsStorage
            .split(separator: ",")
            .compactMap { UUID(uuidString: String($0)) })
    }

    var body: some View {
        VStack(spacing: 0) {
            filterField

            List(selection: $manager.selectedProjectID) {
                ForEach(visibleBlocks, id: \.parent.id) { parent, kids in
                    sidebarRow(project: parent, indent: 0, hasChildren: !kids.isEmpty)
                        .tag(parent.id)
                        .contextMenu { contextMenu(for: parent) }
                    if !kids.isEmpty && (isFiltering || !collapsedParents.contains(parent.id)) {
                        ForEach(kids) { child in
                            sidebarRow(project: child, indent: 1, hasChildren: false)
                                .tag(child.id)
                                .contextMenu { contextMenu(for: child) }
                        }
                    }
                }
                // `moveTopLevelBlocks` maps the List's offsets onto the
                // unfiltered top-level order, so a drag on a filtered list
                // would reorder the wrong rows. Reordering waits for the
                // filter to clear.
                .onMove(perform: moveHandler)
            }
            .listStyle(.sidebar)
            .dropDestination(for: URL.self) { urls, _ in
                guard let folder = urls.first(where: isDirectory) else { return false }
                editorTarget = .add(seedFolder: folder)
                return true
            }

            Divider()

            HStack {
                Button {
                    editorTarget = .add(seedFolder: nil)
                } label: {
                    Label(String(localized: "sidebar.add_project"), systemImage: "plus")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.borderless)
                .padding(8)
            }
        }
        .navigationSplitViewColumnWidth(min: 220, ideal: 260)
    }

    /// Laid out as an ordinary row above the list rather than via
    /// `.searchable(placement: .sidebar)`, which hoists the field into the
    /// column chrome without insetting a sidebar whose root is a `VStack` —
    /// the first project row ended up underneath it.
    private var filterField: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(String(localized: "sidebar.filter.prompt"), text: $query)
                .textFieldStyle(.plain)
                .onExitCommand { query = "" }
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(String(localized: "sidebar.filter.clear"))
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    // MARK: - Hierarchy helpers

    private var topLevelProjects: [Project] {
        manager.projects.filter { $0.parentProjectID == nil }
    }

    private func children(of id: Project.ID) -> [Project] {
        manager.projects.filter { $0.parentProjectID == id }
    }

    private var isFiltering: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var visibleBlocks: [(parent: Project, children: [Project])] {
        let visible = SidebarFilter.visibleIDs(projects: manager.projects, query: query) { id in
            guard case .status(let status)? = statusStore.result(for: id) else { return nil }
            return status.branch
        }
        return topLevelProjects
            .filter { visible.contains($0.id) }
            .map { parent in
                (parent: parent, children: children(of: parent.id).filter { visible.contains($0.id) })
            }
    }

    private var moveHandler: ((IndexSet, Int) -> Void)? {
        guard !isFiltering else { return nil }
        return { moveTopLevelBlocks(fromOffsets: $0, toOffset: $1) }
    }

    /// Translates a top-level `.onMove` (which only knows about block
    /// indices) into a flat-array reorder, keeping each parent's children
    /// glued underneath. The List's `.onMove` semantics: `destination` is
    /// the slot index in the *original* top-level order to insert before.
    private func moveTopLevelBlocks(fromOffsets source: IndexSet, toOffset destination: Int) {
        var blocks: [[Project]] = topLevelProjects.map { parent in
            [parent] + children(of: parent.id)
        }
        let moving = source.sorted().map { blocks[$0] }
        for index in source.sorted(by: >) {
            blocks.remove(at: index)
        }
        let shift = source.filter { $0 < destination }.count
        blocks.insert(contentsOf: moving, at: destination - shift)
        manager.replaceProjectsOrder(blocks.flatMap { $0 })
    }

    @ViewBuilder
    private func contextMenu(for project: Project) -> some View {
        // Action closures run inside the menu's event-tracking runloop
        // mode; setting @State here leaves the resulting `.sheet` queued
        // until the runloop returns to default — which used to wait until
        // the app lost focus. Async hop lets the menu tear down first.
        // Plain NSWorkspace calls don't present a sheet, so they skip it.
        Button(String(localized: "sidebar.row.open_in_finder")) {
            NSWorkspace.shared.open(project.path)
        }
        Button(String(localized: "sidebar.row.open_in_terminal")) {
            openInTerminal(project)
        }
        Divider()
        Button(String(localized: "sidebar.row.edit")) {
            DispatchQueue.main.async {
                editorTarget = .edit(project)
            }
        }
        Button(String(localized: "sidebar.row.duplicate")) {
            DispatchQueue.main.async {
                duplicateTarget = project
            }
        }
        Button(role: .destructive) {
            DispatchQueue.main.async {
                requestRemoval(project: project)
            }
        } label: {
            Text(String(localized: "sidebar.row.remove"))
        }
    }

    /// Plain projects skip the confirmation sheet and remove immediately
    /// (preserves the pre-duplicate behavior). Worktree-backed projects
    /// route through `removalTarget` so ContentView can ask whether to also
    /// run `git worktree remove`.
    private func requestRemoval(project: Project) {
        if project.worktreeInfo != nil {
            removalTarget = project
        } else {
            manager.removeProject(id: project.id)
        }
    }

    private func toggleCollapse(_ id: Project.ID) {
        var ids = collapsedParents
        if ids.contains(id) {
            ids.remove(id)
        } else {
            ids.insert(id)
        }
        collapsedParentsStorage = ids.map(\.uuidString).joined(separator: ",")
    }

    /// A dropped item seeds a project only when it's an actual directory —
    /// dropping a file onto the sidebar is rejected rather than creating a
    /// project rooted at a non-folder path.
    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    /// Opens a new Terminal.app session rooted at the project folder. Silent
    /// no-op if Terminal can't be resolved — there's no sensible fallback.
    private func openInTerminal(_ project: Project) {
        guard let terminalURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "com.apple.Terminal"
        ) else { return }
        NSWorkspace.shared.open(
            [project.path],
            withApplicationAt: terminalURL,
            configuration: NSWorkspace.OpenConfiguration(),
            completionHandler: nil
        )
    }

    // MARK: - Row

    @ViewBuilder
    private func sidebarRow(project: Project, indent: Int, hasChildren: Bool) -> some View {
        let session = manager.session(for: project.id)
        HStack(spacing: 5) {
            disclosureCell(for: project.id, hasChildren: hasChildren)

            StatusDot(state: session?.state ?? .stopped)

            VStack(alignment: .leading, spacing: 2) {
                Text(project.name)
                    .lineLimit(1)
                secondaryLine(for: project)
                if let title = session?.terminalTitle {
                    Text(title)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            Spacer(minLength: 4)

            if let session {
                rightSideStatus(for: session)
            }
        }
        .padding(.leading, CGFloat(indent) * 12)
        .padding(.vertical, 2)
        // `.listStyle(.sidebar)` overrides the horizontal half of
        // `listRowInsets` with the source-list table's own row metrics, so
        // negative padding is the only lever that widens the content. Drop it
        // and the name and git line start truncating again at the minimum
        // column width.
        .padding(.horizontal, -6)
    }

    /// A worktree row spends its second line on git state instead of the
    /// path: `<repo>/.worktrees/<branch>` is long, head-truncated, and mostly
    /// restates the row's own name. Everything else — and a worktree whose
    /// first sample hasn't landed — keeps the path.
    @ViewBuilder
    private func secondaryLine(for project: Project) -> some View {
        if project.worktreeInfo != nil, let result = statusStore.result(for: project.id) {
            gitLine(for: project, result: result)
        } else {
            Text(project.displayPath)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.head)
        }
    }

    @ViewBuilder
    private func gitLine(for project: Project, result: GitStatusResult) -> some View {
        switch result {
        case .unavailable:
            Text(String(localized: "sidebar.row.git.missing"))
                .font(.caption)
                .foregroundStyle(.orange)
                .lineLimit(1)
        case .status(let status):
            HStack(spacing: 6) {
                Text(branchLabel(for: status))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if status.ahead > 0 {
                    Text(String(format: String(localized: "sidebar.row.git.ahead"), status.ahead))
                }
                if status.behind > 0 {
                    Text(String(format: String(localized: "sidebar.row.git.behind"), status.behind))
                }
                if status.changedFiles > 0 {
                    Text(String(format: String(localized: "sidebar.row.git.changed"), status.changedFiles))
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .help(comparisonHelp(for: status))
        }
    }

    /// Spells out what the arrows count. Two bare numbers are only
    /// interpretable if you already know which branch this one forked from.
    private func comparisonHelp(for status: GitStatus) -> String {
        guard let ref = status.comparisonRef else { return "" }
        return String(
            format: String(localized: "sidebar.row.git.comparison"),
            status.ahead,
            status.behind,
            ref
        )
    }

    /// The branch git reports right now, not the one `WorktreeInfo` recorded
    /// at creation — a session that switched branches should show where it
    /// actually is, and naming the recorded branch while detached would be a
    /// lie rather than a fallback.
    private func branchLabel(for status: GitStatus) -> String {
        guard let branch = status.branch, !branch.isEmpty else {
            return String(localized: "sidebar.row.git.detached")
        }
        return branch
    }

    /// Renders the chevron toggle for a parent row, or a same-width empty
    /// gutter for children / leaf parents — keeping the status dot column
    /// aligned across the whole sidebar.
    @ViewBuilder
    private func disclosureCell(for id: Project.ID, hasChildren: Bool) -> some View {
        if hasChildren, !isFiltering {
            Button {
                toggleCollapse(id)
            } label: {
                Image(systemName: collapsedParents.contains(id) ? "chevron.right" : "chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: 10, height: 12)
            }
            .buttonStyle(.plain)
            .help(collapsedParents.contains(id)
                  ? String(localized: "sidebar.disclosure.expand")
                  : String(localized: "sidebar.disclosure.collapse"))
        } else {
            Color.clear.frame(width: 10, height: 12)
        }
    }

    @ViewBuilder
    private func rightSideStatus(for session: Session) -> some View {
        switch session.state {
        case .working:
            Text(session.enteredCurrentStateAt, style: .relative)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        case .waitingForPermission:
            attentionLabel(String(localized: "sidebar.row.label.permission"), color: .orange)
        case .waitingForIdle:
            attentionLabel(String(localized: "sidebar.row.label.needs_input"), color: .orange)
        case .blockedByAutoMode:
            attentionLabel(String(localized: "sidebar.row.label.blocked"), color: .red)
        case .errored:
            attentionLabel(String(localized: "sidebar.row.label.errored"), color: .red)
        case .idle:
            if session.hasUnseenOutput {
                unseenOutputDot
            }
        case .starting, .stopped:
            EmptyView()
        }
    }

    private var unseenOutputDot: some View {
        Circle()
            .fill(Color.accentColor)
            .frame(width: 7, height: 7)
            .accessibilityLabel(String(localized: "sidebar.row.label.unseen_output"))
            .help(String(localized: "sidebar.row.unseen_output.help"))
    }

    private func attentionLabel(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2)
            .fontWeight(.semibold)
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
    }
}
