import SwiftUI

struct ContentView: View {
    @State private var manager = SessionManager()
    @State private var editorTarget: ProjectEditorTarget?

    var body: some View {
        NavigationSplitView {
            SidebarView(manager: manager, editorTarget: $editorTarget)
        } detail: {
            DetailPaneView(manager: manager, editorTarget: $editorTarget)
        }
        .sheet(item: $editorTarget) { target in
            ProjectEditorView(
                target: target,
                onSave: { project in
                    switch target {
                    case .add:
                        manager.addProject(project)
                    case .edit:
                        manager.updateProject(project)
                    }
                    editorTarget = nil
                },
                onCancel: {
                    editorTarget = nil
                }
            )
        }
    }
}

#Preview {
    ContentView()
}
