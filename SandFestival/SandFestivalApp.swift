import SwiftUI

@main
struct SandFestivalApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var manager = SessionManager()
    @State private var claudeCodeAdapter = ClaudeCodeAdapter()

    var body: some Scene {
        WindowGroup {
            ContentView(manager: manager, claudeCodeAdapter: claudeCodeAdapter)
                .frame(minWidth: 900, minHeight: 600)
                .task {
                    await attachAdapterIfNeeded()
                }
        }
        .commands {
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
    }

    @ViewBuilder
    private var menuBarLabel: some View {
        let attentionCount = manager.projects
            .compactMap { manager.session(for: $0.id) }
            .filter(\.state.needsAttention)
            .count

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
