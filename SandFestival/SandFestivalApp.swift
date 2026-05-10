import SwiftUI

@main
struct SandFestivalApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var manager = SessionManager()

    var body: some Scene {
        WindowGroup {
            ContentView(manager: manager)
                .frame(minWidth: 900, minHeight: 600)
                .task {
                    await attachAdapterIfNeeded()
                }
        }
    }

    private func attachAdapterIfNeeded() async {
        guard manager.adapter == nil else { return }
        do {
            try await manager.attach(adapter: ClaudeCodeAdapter())
        } catch {
            // Surfaced as a banner in the Task 10 polish pass; for now,
            // the app runs in degraded mode (state machine never leaves
            // idle/working/stopped because hook events don't arrive).
        }
    }
}
