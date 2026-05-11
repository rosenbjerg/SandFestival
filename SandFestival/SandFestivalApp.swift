import SwiftUI

@main
struct SandFestivalApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var manager = SessionManager()
    @State private var claudeCodeAdapter = ClaudeCodeAdapter()
    @State private var attentionPreferences = AttentionPreferences()
    @State private var attentionNotifier: AttentionNotifier?
    @State private var manualHookSheet = false

    var body: some Scene {
        WindowGroup {
            ContentView(
                manager: manager,
                claudeCodeAdapter: claudeCodeAdapter,
                manualHookSheet: $manualHookSheet
            )
                .frame(minWidth: 900, minHeight: 600)
                .task {
                    if attentionNotifier == nil {
                        attentionNotifier = AttentionNotifier(
                            preferences: attentionPreferences,
                            manager: manager
                        )
                    }
                    await attachAdapterIfNeeded()
                }
        }
        .commands {
            CommandGroup(after: .appSettings) {
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

        MenuBarExtra {
            MenuBarContentView(manager: manager)
        } label: {
            menuBarLabel
        }
        .menuBarExtraStyle(.menu)

        Settings {
            AttentionPreferencesView(
                preferences: attentionPreferences,
                notifier: attentionNotifier
            )
        }
    }

    @ViewBuilder
    private var menuBarLabel: some View {
        let attentionCount = manager.attentionSessions.count

        if attentionCount == 0 {
            Image(systemName: "tray")
        } else {
            Label("\(attentionCount)", systemImage: "tray.full.fill")
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
