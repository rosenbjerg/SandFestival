import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // Kick this off as early as possible so the resolved PATH is
        // ready before any auto-start session asks for the spawn env.
        UserShellPath.resolveInBackground()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
