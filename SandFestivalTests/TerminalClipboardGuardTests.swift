import AppKit
import Foundation
import SwiftTerm
import Testing
@testable import SandFestival

@MainActor
@Suite("TerminalClipboardGuard")
struct TerminalClipboardGuardTests {

    @Test("the session terminal routes delegate calls through the guard")
    func guardIsInstalled() {
        let view = SessionTerminalView(frame: CGRect(x: 0, y: 0, width: 640, height: 400))
        #expect(view.terminalDelegate is TerminalClipboardGuard)
    }

    @Test("an OSC 52 clipboard query gets no reply")
    func clipboardQueryIsDenied() async {
        let (view, sent) = makeView()
        view.dataReceived(slice: ArraySlice(Array("\u{1B}]52;c;?\u{07}".utf8)))
        await settle()
        #expect(sent.count == 0)
    }

    @Test("the kitty clipboard protocol is offered no capabilities")
    func kittyClipboardIsDenied() {
        let view = SessionTerminalView(frame: CGRect(x: 0, y: 0, width: 640, height: 400))
        #expect(view.terminalDelegate?.kittyClipboardCapabilities(source: view) == [])
    }

    @Test("other terminal replies still reach the process")
    func repliesStillForward() async {
        let (view, sent) = makeView()
        view.dataReceived(slice: ArraySlice(Array("\u{1B}[6n".utf8)))
        await settle()
        #expect(sent.count > 0)
    }

    final class Counter {
        var count = 0
    }

    private func makeView() -> (SessionTerminalView, Counter) {
        let view = SessionTerminalView(frame: CGRect(x: 0, y: 0, width: 640, height: 400))
        let counter = Counter()
        view.onUserSent = { counter.count += 1 }
        return (view, counter)
    }

    private func settle() async {
        try? await Task.sleep(for: .milliseconds(30))
    }
}
