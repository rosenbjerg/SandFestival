import AppKit
import SwiftUI

struct ContentView: View {
    @Bindable var manager: SessionManager
    @Bindable var claudeCodeAdapter: ClaudeCodeAdapter
    let statusStore: WorktreeStatusStore
    @Binding var manualHookSheet: Bool
    @Binding var updateSheet: Bool
    @Binding var editorTarget: ProjectEditorTarget?
    @State private var duplicateTarget: Project?
    @State private var removalTarget: Project?
    @State private var hookSheetSkipped = false

    var body: some View {
        VStack(spacing: 0) {
            StatusBannerStack(banners: banners)

            NavigationSplitView {
                SidebarView(
                    manager: manager,
                    statusStore: statusStore,
                    editorTarget: $editorTarget,
                    duplicateTarget: $duplicateTarget,
                    removalTarget: $removalTarget
                )
            } detail: {
                DetailPaneView(
                    manager: manager,
                    editorTarget: $editorTarget,
                    duplicateTarget: $duplicateTarget
                )
            }
            .navigationTitle(windowTitle)
            .navigationSubtitle(windowSubtitle)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            manager.markSelectedSessionSeen()
            manager.focusSelectedTerminal()
            statusStore.refreshAll(projects: manager.projects)
        }
        .task(id: manager.selectedProjectID) {
            while !Task.isCancelled {
                if let project = manager.projects.first(where: { $0.id == manager.selectedProjectID }) {
                    statusStore.refresh(project: project)
                }
                try? await Task.sleep(for: .seconds(30))
                while !Task.isCancelled, !NSApp.isActive {
                    try? await Task.sleep(for: .seconds(30))
                }
            }
        }
        .onChange(of: manager.selectedProjectID) { _, _ in
            manager.markSelectedSessionSeen()
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
        .sheet(item: $duplicateTarget) { source in
            ProjectDuplicateView(
                source: source,
                onCreate: { project in
                    manager.addProject(project)
                    duplicateTarget = nil
                },
                onCancel: { duplicateTarget = nil }
            )
        }
        .sheet(item: $removalTarget) { project in
            ProjectRemovalView(
                project: project,
                onTerminate: { await manager.terminateSessionAndWait(id: project.id) },
                onRemove: { manager.removeProject(id: project.id) },
                onClose: { removalTarget = nil }
            )
        }
        .sheet(isPresented: hookSheetBinding) {
            HookInstallSheet(
                adapter: claudeCodeAdapter,
                onInstall: {
                    hookSheetSkipped = false
                    manualHookSheet = false
                },
                onSkip: {
                    hookSheetSkipped = true
                    manualHookSheet = false
                }
            )
        }
        .sheet(isPresented: $updateSheet) {
            UpdateClaudeCodeSheet(
                manager: manager,
                onClose: { updateSheet = false }
            )
        }
    }

    private var windowTitle: String {
        guard let id = manager.selectedProjectID,
              let project = manager.projects.first(where: { $0.id == id })
        else {
            return String(localized: "app.name")
        }
        return project.name
    }

    private var windowSubtitle: String {
        manager.selectedSession()?.terminalTitle ?? ""
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
            get: {
                manualHookSheet
                    || (claudeCodeAdapter.needsInstallation && !hookSheetSkipped)
            },
            set: { newValue in
                guard !newValue else { return }
                manualHookSheet = false
                // Closing a manually opened sheet isn't a decline; only the
                // auto-prompt is sticky-skipped.
                if claudeCodeAdapter.needsInstallation {
                    hookSheetSkipped = true
                }
            }
        )
    }
}

#Preview {
    ContentView(
        manager: SessionManager(),
        claudeCodeAdapter: ClaudeCodeAdapter(),
        statusStore: WorktreeStatusStore(),
        manualHookSheet: .constant(false),
        updateSheet: .constant(false),
        editorTarget: .constant(nil)
    )
}
