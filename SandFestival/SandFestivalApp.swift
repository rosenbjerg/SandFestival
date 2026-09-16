import SwiftUI

@main
struct SandFestivalApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.openWindow) private var openWindow
    @State private var manager = SessionManager()
    @State private var claudeCodeAdapter = ClaudeCodeAdapter()
    @State private var attentionPreferences = AttentionPreferences()
    @State private var attentionNotifier: AttentionNotifier?
    @State private var statusStore = WorktreeStatusStore()
    @State private var keepAwakePreferences = KeepAwakePreferences()
    @State private var keepAwake: KeepAwake?
    @State private var manualHookSheet = false
    @State private var updateSheet = false
    @State private var editorTarget: ProjectEditorTarget?

    var body: some Scene {
        WindowGroup {
            ContentView(
                manager: manager,
                claudeCodeAdapter: claudeCodeAdapter,
                statusStore: statusStore,
                manualHookSheet: $manualHookSheet,
                updateSheet: $updateSheet,
                editorTarget: $editorTarget
            )
                .frame(minWidth: 900, minHeight: 600)
                .task {
                    if attentionNotifier == nil {
                        attentionNotifier = AttentionNotifier(
                            preferences: attentionPreferences,
                            manager: manager
                        )
                    }
                    manager.shouldSurfaceOnActivity = { [attentionPreferences] in
                        attentionPreferences.autoSurfaceActiveProject
                    }
                    manager.sessionDidFinishWork = { [statusStore] project in
                        statusStore.refresh(project: project)
                    }
                    if keepAwake == nil {
                        keepAwake = KeepAwake(preferences: keepAwakePreferences)
                    }
                    manager.anyWorkingDidChange = { [keepAwake] anyWorking in
                        keepAwake?.anyWorking = anyWorking
                    }
                    statusStore.refreshAll(projects: manager.projects)
                    await attachAdapterIfNeeded()
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(String(localized: "menu.new_project")) {
                    editorTarget = .add(seedFolder: nil)
                }
                .keyboardShortcut("n", modifiers: .command)
            }

            CommandGroup(after: .appSettings) {
                Button(String(localized: "menu.update_claude_code")) {
                    updateSheet = true
                }

                Button(String(localized: "menu.login_claude_code")) {
                    openWindow(id: ClaudeCodeLoginWindow.windowID)
                }

                Button(String(localized: "menu.manage_hooks")) {
                    manualHookSheet = true
                }
            }

            CommandGroup(after: .toolbar) {
                Button(String(localized: "view.terminal.font.larger")) {
                    manager.bumpTerminalFontSize(by: 1)
                }
                .keyboardShortcut("+", modifiers: [.command])

                Button(String(localized: "view.terminal.font.smaller")) {
                    manager.bumpTerminalFontSize(by: -1)
                }
                .keyboardShortcut("-", modifiers: [.command])

                Button(String(localized: "view.terminal.font.reset")) {
                    manager.resetTerminalFontSize()
                }
                .keyboardShortcut("0", modifiers: [.command])
            }
        }

        Window(String(localized: "window.claude_login.title"), id: ClaudeCodeLoginWindow.windowID) {
            ClaudeCodeLoginWindow(manager: manager)
        }
        .defaultSize(width: 760, height: 520)

        Settings {
            TabView {
                AttentionPreferencesView(
                    preferences: attentionPreferences,
                    notifier: attentionNotifier
                )
                .tabItem {
                    Label(
                        String(localized: "preferences.tab.attention"),
                        systemImage: "bell.badge"
                    )
                }

                TerminalPreferencesView(manager: manager)
                    .tabItem {
                        Label(
                            String(localized: "preferences.tab.terminal"),
                            systemImage: "terminal"
                        )
                    }

                KeepAwakePreferencesView(preferences: keepAwakePreferences)
                    .tabItem {
                        Label(
                            String(localized: "preferences.tab.power"),
                            systemImage: "powerplug"
                        )
                    }
            }
        }
    }

    private func attachAdapterIfNeeded() async {
        guard manager.adapter == nil else { return }
        do {
            try await manager.attach(adapter: claudeCodeAdapter)
        } catch {
            // Adapter logs the failure via `startupError`. App remains usable.
        }
    }
}
