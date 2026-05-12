import SwiftUI

struct SidebarView: View {
    @Bindable var manager: SessionManager
    @Binding var editorTarget: ProjectEditorTarget?

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $manager.selectedProjectID) {
                ForEach(manager.projects) { project in
                    sidebarRow(project: project)
                        .tag(project.id)
                        .contextMenu {
                            // Action closures run inside the menu's event-
                            // tracking runloop mode; setting @State here
                            // leaves the resulting `.sheet` queued until the
                            // runloop returns to default — which used to
                            // wait until the app lost focus. Async hop lets
                            // the menu tear down first.
                            Button(String(localized: "sidebar.row.edit")) {
                                DispatchQueue.main.async {
                                    editorTarget = .edit(project)
                                }
                            }
                            Button(role: .destructive) {
                                DispatchQueue.main.async {
                                    manager.removeProject(id: project.id)
                                }
                            } label: {
                                Text(String(localized: "sidebar.row.remove"))
                            }
                        }
                }
                .onMove { source, destination in
                    manager.moveProjects(fromOffsets: source, toOffset: destination)
                }
            }
            .listStyle(.sidebar)

            Divider()

            HStack {
                Button {
                    editorTarget = .add
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

    @ViewBuilder
    private func sidebarRow(project: Project) -> some View {
        let session = manager.session(for: project.id)
        HStack(spacing: 8) {
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
        .padding(.vertical, 2)
    }
}
