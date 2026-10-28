import Foundation
import Testing
@testable import SandFestival

@MainActor
@Suite("Session turn summary")
struct SessionTurnSummaryTests {

    @Test("a finished turn's message is summarized")
    func summarizesFinishedTurn() async throws {
        let (manager, session) = try makeSession(summarizer: StubSummarizer(result: .success("Fixed the race")))
        let router = AgentEventRouter(manager: manager)
        session.apply(event: .started)
        session.apply(event: .working)

        router.report(projectID: session.id, finishedTurnMessage: "I fixed the race in HookListener.")
        router.report(projectID: session.id, event: .idle)
        _ = await session.turnSummaryTask?.value

        #expect(session.turnSummary == "Fixed the race")
    }

    @Test("turning summaries off ignores finished turns")
    func offIgnoresTurns() async throws {
        let (manager, session) = try makeSession()
        manager.summarizesTurns = { false }

        AgentEventRouter(manager: manager).report(projectID: session.id, finishedTurnMessage: "All tests pass.")

        #expect(session.turnSummaryTask == nil)
        #expect(session.turnSummary == nil)
    }

    @Test("with no model available the reply's first line is shown")
    func noModelUsesFirstLine() async throws {
        let (manager, session) = try makeSession()
        manager.turnSummarizer = { nil }

        AgentEventRouter(manager: manager).report(projectID: session.id, finishedTurnMessage: "All tests pass.\nDetails follow.")
        _ = await session.turnSummaryTask?.value

        #expect(session.turnSummary == "All tests pass.")
    }

    @Test("clearing summaries empties every session")
    func clearTurnSummaries() async throws {
        let (manager, session) = try makeSession()
        session.summarizeTurn("All tests pass.", with: nil)
        _ = await session.turnSummaryTask?.value

        manager.clearTurnSummaries()

        #expect(session.turnSummary == nil)
    }

    @Test("a summarizer failure falls back to the reply's first line")
    func fallsBackOnFailure() async throws {
        let failing = StubSummarizer(result: .failure(.unavailable))
        let (_, session) = try makeSession(summarizer: failing)

        session.summarizeTurn("# Done\nAll tests pass.", with: failing)
        _ = await session.turnSummaryTask?.value

        #expect(session.turnSummary == "All tests pass.")
    }

    @Test("a summarizer that outlives its timeout falls back")
    func fallsBackOnTimeout() async throws {
        let slow = StubSummarizer(result: .success("Too late"), delay: .seconds(10), timeout: .milliseconds(50))
        let (_, session) = try makeSession(summarizer: slow)

        session.summarizeTurn("All tests pass.", with: slow)
        _ = await session.turnSummaryTask?.value

        #expect(session.turnSummary == "All tests pass.")
    }

    @Test("an implausible summary falls back")
    func fallsBackOnImplausibleSummary() async throws {
        let rambling = StubSummarizer(result: .success(String(repeating: "word ", count: 60)))
        let (_, session) = try makeSession(summarizer: rambling)

        session.summarizeTurn("All tests pass.", with: rambling)
        _ = await session.turnSummaryTask?.value

        #expect(session.turnSummary == "All tests pass.")
    }

    @Test("starting a new turn clears the summary")
    func newTurnClears() async throws {
        let (_, session) = try makeSession()
        session.apply(event: .started)
        session.summarizeTurn("All tests pass.", with: StubSummarizer(result: .success("Ran the tests")))
        _ = await session.turnSummaryTask?.value

        session.apply(event: .working)

        #expect(session.turnSummary == nil)
        #expect(session.turnSummaryTask == nil)
    }

    @Test("a summary that lands after the next turn started is dropped")
    func staleSummaryDropped() async throws {
        let slow = StubSummarizer(result: .success("Ran the tests"), delay: .milliseconds(50))
        let (_, session) = try makeSession(summarizer: slow)
        session.apply(event: .started)
        session.summarizeTurn("All tests pass.", with: slow)
        let task = try #require(session.turnSummaryTask)

        session.apply(event: .working)
        _ = await task.value

        #expect(session.turnSummary == nil)
    }

    @Test("a restarted conversation and a stopped process clear the summary")
    func restartAndStopClear() async throws {
        let (_, session) = try makeSession()
        session.apply(event: .started)
        session.summarizeTurn("All tests pass.", with: StubSummarizer(result: .success("Ran the tests")))
        _ = await session.turnSummaryTask?.value

        session.apply(event: .sessionRestarted)
        #expect(session.turnSummary == nil)

        session.summarizeTurn("All tests pass.", with: StubSummarizer(result: .success("Ran the tests")))
        _ = await session.turnSummaryTask?.value
        session.apply(event: .stopped)
        #expect(session.turnSummary == nil)
    }

    private func makeSession(
        summarizer: StubSummarizer = StubSummarizer(result: .success("Summary"))
    ) throws -> (SessionManager, Session) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SessionTurnSummaryTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("projects.json", isDirectory: false)
        let store = ProjectStore(fileURL: url)
        let project = Project(name: "Alpha", path: URL(fileURLWithPath: "/tmp/alpha"))
        try store.save([project])
        let manager = SessionManager(store: store)
        manager.turnSummarizer = { summarizer }
        let session = try #require(manager.session(for: project.id))
        return (manager, session)
    }
}

private struct StubSummarizer: TurnSummarizer {
    let result: Result<String, TurnSummarizerError>
    var delay: Duration = .zero
    var timeout: Duration = .seconds(5)

    func summarize(_ message: String) async throws -> String {
        try? await Task.sleep(for: delay)
        return try result.get()
    }
}
