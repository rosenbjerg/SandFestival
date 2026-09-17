import AppKit
import SwiftTerm

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

    private func disableSelectionClobbering() {
        allowMouseReporting = false
    }

    var useMetalProvider: (@MainActor () -> Bool)?

    override func send(source: TerminalView, data: ArraySlice<UInt8>) {
        super.send(source: source, data: data)
        guard let onUserSent else { return }
        Task { @MainActor in onUserSent() }
    }

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

    // scrollPosition is 0 both at the top of the scrollback and when there is none yet.
    private var isScrolledUp: Bool {
        canScroll && scrollPosition < 1
    }

    private func setOutputBelowViewport(_ value: Bool) {
        guard value != outputBelowViewport else { return }
        outputBelowViewport = value
        guard let onOutputBelowViewportChanged else { return }
        Task { @MainActor in onOutputBelowViewportChanged(value) }
    }

    override func viewDidMoveToWindow() {
        // super first: SwiftTerm rebinds the renderer on reparent, and setUseMetal must follow.
        super.viewDidMoveToWindow()
        guard window != nil, let useMetalProvider else { return }
        try? setUseMetal(useMetalProvider())
    }
}
