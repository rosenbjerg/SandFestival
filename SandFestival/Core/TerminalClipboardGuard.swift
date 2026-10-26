import Foundation
import SwiftTerm

final class TerminalClipboardGuard: TerminalViewDelegate {
    weak var target: LocalProcessTerminalView?

    func clipboardRead(source: TerminalView) -> Data? {
        nil
    }

    func kittyClipboardCapabilities(source: TerminalView) -> KittyClipboardCapabilities {
        []
    }

    // Every other requirement must forward to `target` — one left to the protocol's default silently changes terminal behavior, so recheck this list on every SwiftTerm bump.
    func clipboardCopy(source: TerminalView, content: Data) {
        target?.clipboardCopy(source: source, content: content)
    }

    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        target?.sizeChanged(source: source, newCols: newCols, newRows: newRows)
    }

    func setTerminalTitle(source: TerminalView, title: String) {
        target?.setTerminalTitle(source: source, title: title)
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        target?.hostCurrentDirectoryUpdate(source: source, directory: directory)
    }

    func send(source: TerminalView, data: ArraySlice<UInt8>) {
        target?.send(source: source, data: data)
    }

    func scrolled(source: TerminalView, position: Double) {
        target?.scrolled(source: source, position: position)
    }

    func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
        target?.requestOpenLink(source: source, link: link, params: params)
    }

    func bell(source: TerminalView) {
        target?.bell(source: source)
    }

    func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {
        target?.iTermContent(source: source, content: content)
    }

    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {
        target?.rangeChanged(source: source, startY: startY, endY: endY)
    }

    func programStatusChanged(source: TerminalView, records: [TerminalProgramStatus]) {
        target?.programStatusChanged(source: source, records: records)
    }
}
