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
        let rows = view.terminalDimensions.rows

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
        let rows = view.terminalDimensions.rows
        view.changeScrollback(20)

        feed(view, lines(rows + 200))
        view.scrollUp(lines: 5)
        feed(view, lines(3))
        await settle()

        #expect(events.value == [true])
    }

    @Test("an in-place redraw while scrolled up is not new output")
    func redrawIsNotNewOutput() async {
        let (view, events) = makeView()
        let rows = view.terminalDimensions.rows

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
        let rows = view.terminalDimensions.rows

        feed(view, lines(rows * 3))
        feed(view, lines(rows))
        await settle()

        #expect(events.value.isEmpty)
    }

    @Test("scrolling up and back down without output stays quiet")
    func scrollOnlyIsQuiet() async {
        let (view, events) = makeView()
        let rows = view.terminalDimensions.rows

        feed(view, lines(rows * 3))
        view.scrollUp(lines: 5)
        view.scroll(toPosition: 1)
        await settle()

        #expect(events.value.isEmpty)
    }

    @Test("an output-driven scroll that lands before the main hop doesn't hide the drop")
    func outputScrollBeforeHop() async {
        let (view, events) = makeView()
        let rows = view.terminalDimensions.rows

        feed(view, lines(rows * 3))
        view.scrollUp(lines: 5)
        view.feed(byteArray: ArraySlice(Array(lines(1).utf8)))
        view.processOutputApplied()
        view.scrolled(source: view, position: view.scrollPosition)
        await settle()

        #expect(events.value == [true])
    }

    @Test("output from a real process reaches the observer")
    func realProcessWiring() async {
        let (view, events) = makeView()
        let rows = view.terminalDimensions.rows
        view.startProcess(
            executable: "/bin/sh",
            args: ["-c", "stty raw -echo; exec cat"],
            environment: nil,
            execName: nil,
            currentDirectory: nil
        )
        defer { view.terminate() }

        send(view, "sf-ready\r\n")
        #expect(await poll { bufferText(view).contains("sf-ready") })
        send(view, rawLines(rows * 3) + "sf-filled\r\n")
        #expect(await poll { bufferText(view).contains("sf-filled") })
        await settle()
        #expect(events.value.isEmpty)

        view.scrollUp(lines: 5)
        send(view, rawLines(3))
        #expect(await poll { events.value == [true] })
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
        view.feed(byteArray: ArraySlice(Array(text.utf8)))
        view.outputApplied()
    }

    private func send(_ view: SessionTerminalView, _ text: String) {
        view.process.send(data: ArraySlice(Array(text.utf8)))
    }

    private func bufferText(_ view: SessionTerminalView) -> String {
        String(decoding: view.getBufferAsData(), as: UTF8.self)
    }

    private func lines(_ count: Int) -> String {
        String(repeating: "line\n", count: count)
    }

    private func rawLines(_ count: Int) -> String {
        String(repeating: "line\r\n", count: count)
    }

    private func poll(timeout: Duration = .seconds(5), _ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while !condition() {
            guard ContinuousClock.now < deadline else { return false }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return true
    }

    private func settle() async {
        try? await Task.sleep(for: .milliseconds(30))
    }
}
