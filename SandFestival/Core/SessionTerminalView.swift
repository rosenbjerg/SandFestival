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
    var onOutputBelowViewportChanged: (@MainActor (Bool) -> Void)?
    private var outputBelowViewport = false

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
    /// preference the moment it enters a window. A `Session` builds its view
    /// long before SwiftUI mounts it, so deferring to `viewDidMoveToWindow`
    /// is what makes the toggle's current value apply to sessions that were
    /// never on screen. SwiftTerm rebinds the renderer on reparent from its
    /// own `viewDidMoveToWindow` (since 1.14.0), so call `super` first and
    /// let that run before `setUseMetal`.
    var useMetalProvider: (@MainActor () -> Bool)?

    override func send(source: TerminalView, data: ArraySlice<UInt8>) {
        super.send(source: source, data: data)
        guard let onUserSent else { return }
        // `send` runs on the AppKit main thread. Hop through MainActor
        // explicitly so the captured closure is callable from a Sendable
        // override without isolation gymnastics.
        Task { @MainActor in onUserSent() }
    }

    /// Compares `scrollPosition` across the feed rather than treating any
    /// bytes as new output: Claude Code's spinner and input box redraw in
    /// place constantly, and only real new lines move the position. Observes
    /// only — viewport pinning is SwiftTerm's, see CLAUDE.md.
    override func dataReceived(slice: ArraySlice<UInt8>) {
        let before = scrollPosition
        super.dataReceived(slice: slice)
        if isScrolledUp, scrollPosition < before {
            setOutputBelowViewport(true)
        }
    }

    override func scrolled(source: TerminalView, position: Double) {
        super.scrolled(source: source, position: position)
        if !isScrolledUp {
            setOutputBelowViewport(false)
        }
    }

    /// `scrollPosition` reads 0 both at the top of the scrollback and when
    /// there is none yet; `canScroll` tells them apart.
    private var isScrolledUp: Bool {
        canScroll && scrollPosition < 1
    }

    /// Edge-triggered on purpose: `scrolled` fires for every line the
    /// terminal scrolls while pinned at the bottom, and the SwiftUI listener
    /// re-renders on every call it receives.
    private func setOutputBelowViewport(_ value: Bool) {
        guard value != outputBelowViewport else { return }
        outputBelowViewport = value
        guard let onOutputBelowViewportChanged else { return }
        Task { @MainActor in onOutputBelowViewportChanged(value) }
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
