import SwiftTerm

/// Subclass that exposes user keystrokes via `onUserSent`. SwiftTerm's
/// `LocalProcessTerminalView` already routes typed bytes through
/// `send(source:data:)` to the PTY; overriding lets us observe that
/// traffic without breaking the forwarding path. Used by `Session` to
/// clear `waitingForIdle` when the user types — Claude Code emits no
/// hook on `AskUserQuestion` cancel via Ctrl+C, so terminal input is
/// the most reliable "user is engaging again" signal we have.
final class SessionTerminalView: LocalProcessTerminalView {
    var onUserSent: (@MainActor () -> Void)?

    override func send(source: TerminalView, data: ArraySlice<UInt8>) {
        super.send(source: source, data: data)
        guard let onUserSent else { return }
        // `send` runs on the AppKit main thread. Hop through MainActor
        // explicitly so the captured closure is callable from a Sendable
        // override without isolation gymnastics.
        Task { @MainActor in onUserSent() }
    }
}
