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

    override init(frame: CGRect) {
        super.init(frame: frame)
        disableSelectionClobbering()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        disableSelectionClobbering()
    }

    /// Keeps a manual text selection alive while Claude streams output, so the
    /// user can actually drag-select and copy from a running session.
    ///
    /// SwiftTerm wipes the selection on *every* feed (`feedPrepare` calls
    /// `selection.active = false`) and again on *every* linefeed — so each
    /// chunk of streaming output cleared whatever the user had highlighted.
    /// Both clears are gated solely on `allowMouseReporting`; SwiftTerm's own
    /// comments document turning it off as the way to "preserve manual
    /// selection while output is streaming". `feedPrepare` is `internal` and
    /// can't be overridden from here, so flipping this flag is the only lever.
    ///
    /// The cost is that mouse events are no longer forwarded to apps that
    /// request mouse tracking. For this dashboard that's the right trade: the
    /// session is the Claude Code TUI, which drives output through the primary
    /// buffer with linefeeds (never mouse mode — that's why selection cleared),
    /// and the whole point of selecting is to read and copy that output. With
    /// the flag off, the view handles the mouse locally (drag-select, scroll).
    private func disableSelectionClobbering() {
        allowMouseReporting = false
    }

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

    /// Keeps the viewport pinned when the user has scrolled up, instead of
    /// snapping to the bottom on every chunk of Claude output.
    ///
    /// SwiftTerm's emulator core already supports this — `Terminal.scroll`
    /// only resets `yDisp` to the bottom when its `userScrolling` flag is
    /// false — but the macOS view layer never sets that flag from the actual
    /// scroll position (its own same-named property is written during
    /// scrollbar-knob drags and never read). The core flag is `internal` to
    /// SwiftTerm and unreachable from here, so we restore the scroll position
    /// ourselves after `super` has fed the bytes and snapped to the bottom.
    ///
    /// PTY data arrives on `DispatchQueue.main` (LocalProcess's default
    /// queue), so touching the view here is main-thread-safe. Exact while the
    /// scrollback buffer isn't full; once output starts trimming the oldest
    /// lines the pinned content drifts toward the bottom (SwiftTerm doesn't
    /// expose the trim count), which a larger scrollback setting defers.
    override func dataReceived(slice: ArraySlice<UInt8>) {
        // `canScroll` is false in the alternate buffer (full-screen TUIs) and
        // when everything already fits on screen — treat both as "at bottom"
        // so normal follow-the-output behavior is untouched.
        let wasAtBottom = !canScroll || scrollPosition >= 1.0
        let savedRow = getTerminal().buffer.yDisp

        super.dataReceived(slice: slice)

        guard !wasAtBottom else { return }
        // `super` snapped yDisp to the bottom; restore the user's row, clamped
        // to the new bottom so a buffer trim can't push us past the end.
        scrollTo(row: min(savedRow, getTerminal().buffer.yDisp))
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
