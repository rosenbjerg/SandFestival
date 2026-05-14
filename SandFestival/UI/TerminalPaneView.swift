import AppKit
import SwiftTerm
import SwiftUI

/// Hosts a `LocalProcessTerminalView` whose lifetime is owned by a `Session`,
/// not by SwiftUI. Returning the existing instance from `makeNSView` lets
/// scrollback and the underlying PTY survive sidebar selection changes.
///
/// `isVisible` toggles `NSView.isHidden` rather than SwiftUI `.opacity(0)` so
/// AppKit skips drawing non-selected sessions entirely — at alpha 0 the layer
/// is still asked to paint dirty rects on every PTY update.
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
            // The layer-backed view preserves contents across hide, but a row
            // that dirtied while hidden may not have been redrawn. Force a
            // full-bounds paint so the first visible frame is fresh.
            nsView.needsDisplay = true
        }
    }
}
