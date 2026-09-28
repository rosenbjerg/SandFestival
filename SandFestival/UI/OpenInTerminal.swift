import AppKit

enum OpenInTerminal {
    static func open(_ path: URL) {
        guard let terminalURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "com.apple.Terminal"
        ) else { return }
        NSWorkspace.shared.open(
            [path],
            withApplicationAt: terminalURL,
            configuration: NSWorkspace.OpenConfiguration(),
            completionHandler: nil
        )
    }
}
