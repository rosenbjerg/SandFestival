import AppKit
import SwiftTerm
import Synchronization

final class SessionTerminalView: LocalProcessTerminalView {
    var onUserSent: (@MainActor () -> Void)?
    var onOutputBelowViewportChanged: (@MainActor (Bool) -> Void)?
    private var outputBelowViewport = false
    private var lastObservedPosition: Double = 0
    nonisolated private let pendingOutputBatches = Mutex(0)

    override init(frame: CGRect) {
        super.init(frame: frame)
        disableSelectionClobbering()
        observeProcessOutput()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        disableSelectionClobbering()
        observeProcessOutput()
    }

    private func disableSelectionClobbering() {
        allowMouseReporting = false
    }

    private func observeProcessOutput() {
        setProcessOutputHandler { [weak self] in
            self?.processOutputApplied()
        }
    }

    nonisolated func processOutputApplied() {
        pendingOutputBatches.withLock { $0 += 1 }
        Task { @MainActor [weak self] in self?.outputApplied() }
    }

    func outputApplied() {
        pendingOutputBatches.withLock { $0 = max(0, $0 - 1) }
        let position = scrollPosition
        if isScrolledUp, position < lastObservedPosition {
            setOutputBelowViewport(true)
        }
        lastObservedPosition = position
    }

    var useMetalProvider: (@MainActor () -> Bool)?

    override func send(source: TerminalView, data: ArraySlice<UInt8>) {
        super.send(source: source, data: data)
        guard let onUserSent else { return }
        Task { @MainActor in onUserSent() }
    }

    override func scrolled(source: TerminalView, position: Double) {
        super.scrolled(source: source, position: position)
        if !isScrolledUp {
            setOutputBelowViewport(false)
        }
        // Output-driven scrolls can land before outputApplied; moving the baseline then would hide the drop.
        if pendingOutputBatches.withLock({ $0 }) == 0 {
            lastObservedPosition = scrollPosition
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
