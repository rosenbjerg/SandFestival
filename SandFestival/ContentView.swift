import AppKit
import SwiftUI

struct ContentView: View {
    @Bindable var manager: SessionManager
    @Bindable var claudeCodeAdapter: ClaudeCodeAdapter
    @State private var editorTarget: ProjectEditorTarget?
    @State private var hookSheetSkipped = false

    var body: some View {
        VStack(spacing: 0) {
            StatusBannerStack(banners: banners)

            NavigationSplitView {
                SidebarView(manager: manager, editorTarget: $editorTarget)
            } detail: {
                DetailPaneView(manager: manager, editorTarget: $editorTarget)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            manager.focusSelectedTerminal()
        }
        .onChange(of: manager.selectedProjectID) { _, _ in
            manager.focusSelectedTerminal()
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

    private var banners: [StatusBannerStack.Banner] {
        var result: [StatusBannerStack.Banner] = []
        if let error = claudeCodeAdapter.startupError {
            result.append(.init(
                message: String(format: String(localized: "banner.adapter_startup_failed"), error),
                severity: .error,
                dismiss: { claudeCodeAdapter.clearStartupError() }
            ))
        }
        if let error = claudeCodeAdapter.lastInstallError {
            result.append(.init(
                message: error,
                severity: .warning,
                dismiss: { claudeCodeAdapter.clearLastInstallError() }
            ))
        }
        if let error = manager.lastPersistError {
            result.append(.init(
                message: String(format: String(localized: "banner.projects_persist_failed"), error),
                severity: .warning,
                dismiss: { manager.clearPersistError() }
            ))
        }
        return result
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
