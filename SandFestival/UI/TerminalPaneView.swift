import AppKit
import SwiftTerm
import SwiftUI

struct TerminalPaneView: NSViewRepresentable {
    let terminalView: LocalProcessTerminalView
    let isVisible: Bool

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        terminalView.isHidden = !isVisible
        return terminalView
    }

    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {
        let shouldHide = !isVisible
        guard nsView.isHidden != shouldHide else { return }
        nsView.isHidden = shouldHide
        if isVisible {
            // Rows dirtied while hidden aren't redrawn on unhide without this.
            nsView.needsDisplay = true
        }
    }
}
