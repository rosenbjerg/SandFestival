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

            if let session, session.state.needsAttention, manager.selectedProjectID != project.id {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.orange)
                    .imageScale(.small)
            }

            if let lastActivityAt = session?.lastActivityAt {
                Text(lastActivityAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 2)
    }
}
