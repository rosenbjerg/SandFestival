import SwiftUI

struct ContentView: View {
    @Bindable var manager: SessionManager
    @Bindable var claudeCodeAdapter: ClaudeCodeAdapter
    @State private var editorTarget: ProjectEditorTarget?
    @State private var hookSheetSkipped = false

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
                    case .add: manager.addProject(project)
                    case .edit: manager.updateProject(project)
                    }
                    editorTarget = nil
                },
                onCancel: { editorTarget = nil }
            )
        }
        .sheet(isPresented: hookSheetBinding) {
            HookInstallSheet(
                adapter: claudeCodeAdapter,
                onInstall: { hookSheetSkipped = false },
                onSkip: { hookSheetSkipped = true }
            )
        }
    }

    private var hookSheetBinding: Binding<Bool> {
        Binding(
            get: { claudeCodeAdapter.needsInstallation && !hookSheetSkipped },
            set: { newValue in
                if !newValue {
                    hookSheetSkipped = true
                }
            }
        )
    }
}

#Preview {
    ContentView(
        manager: SessionManager(),
        claudeCodeAdapter: ClaudeCodeAdapter()
    )
}
