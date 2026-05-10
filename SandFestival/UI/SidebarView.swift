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
                            Button(String(localized: "sidebar.row.edit")) {
                                editorTarget = .edit(project)
                            }
                            Button(role: .destructive) {
                                manager.removeProject(id: project.id)
                            } label: {
                                Text(String(localized: "sidebar.row.remove"))
                            }
                        }
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
            }

            Spacer(minLength: 4)

            if let session {
                rightSideStatus(for: session)
            }
        }
        .padding(.vertical, 2)
    }
}
