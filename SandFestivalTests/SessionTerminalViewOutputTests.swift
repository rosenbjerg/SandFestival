import AppKit
import Foundation
import SwiftTerm
import Testing
@testable import SandFestival

@MainActor
@Suite("SessionTerminalView output-below-viewport")
struct SessionTerminalViewOutputTests {

    @Test("output arriving below a scrolled-up viewport fires once, and scrolling back down clears it once")
    func edgesOnly() async {
        let (view, events) = makeView()
        let rows = view.getTerminal().rows

        feed(view, lines(rows * 3))
        await settle()
        #expect(events.value.isEmpty)

        view.scrollUp(lines: 5)
        feed(view, lines(1))
        feed(view, lines(1))
        feed(view, lines(1))
        await settle()
        #expect(events.value == [true])

        view.scroll(toPosition: 1)
        await settle()
        #expect(events.value == [true, false])
    }

    @Test("output still registers once the scrollback is full and lines are being trimmed")
    func fullScrollbackStillFires() async {
        let (view, events) = makeView()
        let rows = view.getTerminal().rows
        view.getTerminal().changeScrollback(20)

        feed(view, lines(rows + 200))
        view.scrollUp(lines: 5)
        feed(view, lines(3))
        await settle()

        #expect(events.value == [true])
    }

    @Test("an in-place redraw while scrolled up is not new output")
    func redrawIsNotNewOutput() async {
        let (view, events) = makeView()
        let rows = view.getTerminal().rows

        feed(view, lines(rows * 3))
        view.scrollUp(lines: 5)
        feed(view, "\rworking…")
        feed(view, "\r\u{1B}[2Kworking… still")
        await settle()

        #expect(events.value.isEmpty)
    }

    @Test("output while pinned at the bottom never fires")
    func pinnedIsQuiet() async {
        let (view, events) = makeView()
        let rows = view.getTerminal().rows

        feed(view, lines(rows * 3))
        feed(view, lines(rows))
        await settle()

        #expect(events.value.isEmpty)
    }

    @Test("scrolling up and back down without output stays quiet")
    func scrollOnlyIsQuiet() async {
        let (view, events) = makeView()
        let rows = view.getTerminal().rows

        feed(view, lines(rows * 3))
        view.scrollUp(lines: 5)
        view.scroll(toPosition: 1)
        await settle()

        #expect(events.value.isEmpty)
    }

    // MARK: - Helpers

    final class Events {
        var value: [Bool] = []
    }

    private func makeView() -> (SessionTerminalView, Events) {
        let view = SessionTerminalView(frame: CGRect(x: 0, y: 0, width: 640, height: 400))
        let events = Events()
        view.onOutputBelowViewportChanged = { events.value.append($0) }
        return (view, events)
    }

    private func feed(_ view: SessionTerminalView, _ text: String) {
        view.dataReceived(slice: ArraySlice(Array(text.utf8)))
    }

    private func lines(_ count: Int) -> String {
        String(repeating: "line\n", count: count)
    }

    /// The change callback hops through a `Task` onto the main actor.
    private func settle() async {
        try? await Task.sleep(for: .milliseconds(30))
    }
}
