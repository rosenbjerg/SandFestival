import AppKit
import SwiftTerm
import Synchronization

final class SessionTerminalView: LocalProcessTerminalView {
    var onUserSent: (@MainActor () -> Void)?
    var onOutputBelowViewportChanged: (@MainActor (Bool) -> Void)?
    var acceptsPastedImagePaths: (@MainActor () -> Bool)?
    private var outputBelowViewport = false
    private var lastObservedPosition: Double = 0
    nonisolated private let pendingOutputBatches = Mutex(0)
    private let clipboardGuard = TerminalClipboardGuard()
    private var controlVMonitor: Any?

    override init(frame: CGRect) {
        super.init(frame: frame)
        disableSelectionClobbering()
        observeProcessOutput()
        installClipboardGuard()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        disableSelectionClobbering()
        observeProcessOutput()
        installClipboardGuard()
    }

    private func installClipboardGuard() {
        clipboardGuard.target = self
        terminalDelegate = clipboardGuard
    }

    override func paste(_ sender: Any) {
        if !pasteImage(trigger: .paste) {
            super.paste(sender)
        }
    }

    private func updateControlVMonitor() {
        if window == nil {
            if let controlVMonitor { NSEvent.removeMonitor(controlVMonitor) }
            controlVMonitor = nil
        } else if controlVMonitor == nil {
            controlVMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, self.isControlV(event), event.window === self.window,
                      self.window?.firstResponder === self,
                      self.pasteImage(trigger: .controlV)
                else { return event }
                return nil
            }
        }
    }

    private func isControlV(_ event: NSEvent) -> Bool {
        event.type == .keyDown
            && event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .control
            && event.charactersIgnoringModifiers?.lowercased() == "v"
    }

    private func pasteImage(trigger: ImagePaste.Trigger) -> Bool {
        guard acceptsPastedImagePaths?() == true else { return false }
        let pasteboard = NSPasteboard.general
        let wantsImage = ImagePaste.shouldPasteImage(
            trigger: trigger,
            hasText: ImagePaste.hasText(pasteboard),
            hasImage: ImagePaste.hasImage(pasteboard)
        )
        guard wantsImage,
              let png = ImagePaste.pngData(from: pasteboard),
              let url = try? ImagePaste.store(png)
        else { return false }
        pasteText(url.path)
        return true
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
        updateControlVMonitor()
        guard window != nil, let useMetalProvider else { return }
        try? setUseMetal(useMetalProvider())
    }
}
