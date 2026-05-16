import SwiftUI

struct SidebarView: View {
    @Bindable var manager: SessionManager
    @Binding var editorTarget: ProjectEditorTarget?
    @Binding var duplicateTarget: Project?
    @Binding var removalTarget: Project?

    /// In-memory only — collapse state resets every app launch. Parents
    /// default to expanded; this set holds the ids the user has folded up.
    @State private var collapsedParents: Set<Project.ID> = []

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $manager.selectedProjectID) {
                ForEach(topLevelProjects) { parent in
                    let kids = children(of: parent.id)
                    sidebarRow(project: parent, indent: 0, hasChildren: !kids.isEmpty)
                        .tag(parent.id)
                        .contextMenu { contextMenu(for: parent) }
                    if !kids.isEmpty && !collapsedParents.contains(parent.id) {
                        ForEach(kids) { child in
                            sidebarRow(project: child, indent: 1, hasChildren: false)
                                .tag(child.id)
                                .contextMenu { contextMenu(for: child) }
                        }
                    }
                }
                .onMove { source, destination in
                    moveTopLevelBlocks(fromOffsets: source, toOffset: destination)
                }
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

    // MARK: - Hierarchy helpers

    private var topLevelProjects: [Project] {
        manager.projects.filter { $0.parentProjectID == nil }
    }

    private func children(of id: Project.ID) -> [Project] {
        manager.projects.filter { $0.parentProjectID == id }
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
        if collapsedParents.contains(id) {
            collapsedParents.remove(id)
        } else {
            collapsedParents.insert(id)
        }
    }

    /// A dropped item seeds a project only when it's an actual directory —
    /// dropping a file onto the sidebar is rejected rather than creating a
    /// project rooted at a non-folder path.
    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    // MARK: - Row

    @ViewBuilder
    private func sidebarRow(project: Project, indent: Int, hasChildren: Bool) -> some View {
        let session = manager.session(for: project.id)
        HStack(spacing: 6) {
            disclosureCell(for: project.id, hasChildren: hasChildren)

            StatusDot(state: session?.state ?? .stopped)

            VStack(alignment: .leading, spacing: 2) {
                Text(project.name)
                    .lineLimit(1)
                Text(project.path.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
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
        .padding(.leading, CGFloat(indent) * 14)
        .padding(.vertical, 2)
    }

    /// Renders the chevron toggle for a parent row, or a same-width empty
    /// gutter for children / leaf parents — keeping the status dot column
    /// aligned across the whole sidebar.
    @ViewBuilder
    private func disclosureCell(for id: Project.ID, hasChildren: Bool) -> some View {
        if hasChildren {
            Button {
                toggleCollapse(id)
            } label: {
                Image(systemName: collapsedParents.contains(id) ? "chevron.right" : "chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: 12, height: 12)
            }
            .buttonStyle(.plain)
            .help(collapsedParents.contains(id)
                  ? String(localized: "sidebar.disclosure.expand")
                  : String(localized: "sidebar.disclosure.collapse"))
        } else {
            Color.clear.frame(width: 12, height: 12)
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
        case .starting, .idle, .stopped:
            EmptyView()
        }
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
