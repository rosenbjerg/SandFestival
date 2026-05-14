import AppKit
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

    /// Set by SessionManager so this view picks up the current GPU-rendering
    /// preference the moment it enters a window. SwiftTerm requires
    /// `setUseMetal` be called after the view is added to a window, so the
    /// call is deferred from session-init time to `viewDidMoveToWindow`.
    var useMetalProvider: (@MainActor () -> Bool)?

    override func send(source: TerminalView, data: ArraySlice<UInt8>) {
        super.send(source: source, data: data)
        guard let onUserSent else { return }
        // `send` runs on the AppKit main thread. Hop through MainActor
        // explicitly so the captured closure is callable from a Sendable
        // override without isolation gymnastics.
        Task { @MainActor in onUserSent() }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil, let useMetalProvider else { return }
        // Best-effort: a missing GPU on this host throws MetalError and we
        // silently stay on the CoreGraphics path. The toggle's caption tells
        // users the feature is opt-in; logging here would just add noise.
        try? setUseMetal(useMetalProvider())
    }
}
