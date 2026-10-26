import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // Before anything can auto-start: the first spawn env waits on this.
        UserShellPath.resolveInBackground()
        ImagePaste.purge()
    }

    func applicationWillTerminate(_ notification: Notification) {
        ImagePaste.purge()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
