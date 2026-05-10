import AppKit
import SwiftTerm
import SwiftUI

/// Hosts a `LocalProcessTerminalView` whose lifetime is owned by a `Session`,
/// not by SwiftUI. Returning the existing instance from `makeNSView` lets
/// scrollback and the underlying PTY survive sidebar selection changes.
struct TerminalPaneView: NSViewRepresentable {
    let terminalView: LocalProcessTerminalView

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        terminalView
    }

    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {}
}
