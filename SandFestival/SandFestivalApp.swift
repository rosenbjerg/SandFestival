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
    }

    private func attachAdapterIfNeeded() async {
        guard manager.adapter == nil else { return }
        do {
            try await manager.attach(adapter: claudeCodeAdapter)
        } catch {
            // Adapter logs the failure via `startupError`. The app remains
            // usable; sessions just won't get state updates from hooks.
        }
    }
}
