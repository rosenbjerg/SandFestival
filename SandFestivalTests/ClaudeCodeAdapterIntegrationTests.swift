import Foundation
import Testing
@testable import SandFestival

/// End-to-end coverage for the Claude Code adapter's hook ingestion path:
/// HookListener → HookRequestParser → HookPayloadDecoder →
/// HookPayloadTranslator → SessionBindingStore → AgentEventSink. The pieces
/// each have unit tests; this suite makes sure they still fit together
/// after refactors.
@MainActor
@Suite("ClaudeCodeAdapter integration", .serialized)
struct ClaudeCodeAdapterIntegrationTests {

    @Test("SessionStart for a pending spawn dispatches .started to the sink")
    func sessionStartRoutesAsStarted() async throws {
        let env = try await IntegrationEnvironment.start(port: 51790)
        defer { env.teardown() }

        let project = env.makeProject(cwdName: "sf-int-\(UUID().uuidString)")
        _ = env.adapter.prepareSpawn(project: project)

        try await env.postHook([
            "session_id": "sess-start",
            "hook_event_name": "SessionStart",
            "cwd": project.path.path,
        ], projectID: project.id)

        try await env.sink.waitForEvents(1)
        let received = try #require(env.sink.events.first)
        #expect(received.projectID == project.id)
        #expect(received.event == .started)
    }

    @Test("Notification with permission language maps to .waitingForPermission")
    func notificationPermissionRoutesAsWaiting() async throws {
        let env = try await IntegrationEnvironment.start(port: 51792)
        defer { env.teardown() }

        let project = env.makeProject(cwdName: "sf-int-\(UUID().uuidString)")
        _ = env.adapter.prepareSpawn(project: project)

        // Bind the session via SessionStart, then drain the resulting event so
        // we can assert on the follow-up cleanly.
        try await env.postHook([
            "session_id": "sess-perm",
            "hook_event_name": "SessionStart",
            "cwd": project.path.path,
        ], projectID: project.id)
        try await env.sink.waitForEvents(1)
        env.sink.drainEvents()

        try await env.postHook([
            "session_id": "sess-perm",
            "hook_event_name": "Notification",
            "message": "Claude needs your permission to use Bash",
        ])
        try await env.sink.waitForEvents(1)
        let received = try #require(env.sink.events.first)
        #expect(received.projectID == project.id)
        #expect(received.event == .waitingForPermission)
    }

    @Test("/resume rebinds the new session_id to the same project and emits no .stopped")
    func resumeRebindsToSameProject() async throws {
        let env = try await IntegrationEnvironment.start(port: 51794)
        defer { env.teardown() }

        let project = env.makeProject(cwdName: "sf-int-\(UUID().uuidString)")
        _ = env.adapter.prepareSpawn(project: project)

        // 1. Original session starts.
        try await env.postHook([
            "session_id": "sess-original",
            "hook_event_name": "SessionStart",
            "cwd": project.path.path,
        ], projectID: project.id)
        try await env.sink.waitForEvents(1)
        env.sink.drainEvents()

        // 2. User runs /resume — claude emits SessionEnd for the old id and
        //    SessionStart for a new id, but the OS process keeps running.
        try await env.postHook([
            "session_id": "sess-original",
            "hook_event_name": "SessionEnd",
            "cwd": project.path.path,
        ])
        try await env.postHook([
            "session_id": "sess-resumed",
            "hook_event_name": "SessionStart",
            "cwd": project.path.path,
        ], projectID: project.id)

        // 3. A follow-up event under the new session_id must route to the same
        //    project — this is what proves the rebind worked end-to-end.
        try await env.postHook([
            "session_id": "sess-resumed",
            "hook_event_name": "UserPromptSubmit",
            "cwd": project.path.path,
        ])

        try await env.sink.waitForEvents(2)

        // SessionEnd no longer emits anything, so the only events we expect are
        // .sessionRestarted (the resumed SessionStart, distinguished from a
        // fresh-spawn .started so Session drops the stale conversation title)
        // and .working (from the follow-up UserPromptSubmit). Crucially: no
        // .stopped, and no fresh-spawn .started either.
        let events = env.sink.events
        #expect(events.allSatisfy { $0.projectID == project.id })
        #expect(events.contains { $0.event == .sessionRestarted })
        #expect(events.contains { $0.event == .working })
        #expect(!events.contains { $0.event == .started })
        #expect(!events.contains { $0.event == .stopped })
    }

    @Test("two projects sharing a cwd route each SessionStart to its own project")
    func sharedCwdProjectsRouteIndependently() async throws {
        let env = try await IntegrationEnvironment.start(port: 51795)
        defer { env.teardown() }

        // A "Duplicate…" without a worktree gives the child the parent's path.
        let cwdName = "sf-int-\(UUID().uuidString)"
        let parent = env.makeProject(cwdName: cwdName)
        let child = env.makeProject(cwdName: cwdName)
        #expect(parent.path == child.path)
        _ = env.adapter.prepareSpawn(project: parent)
        _ = env.adapter.prepareSpawn(project: child)

        try await env.postHook([
            "session_id": "sess-parent",
            "hook_event_name": "SessionStart",
            "cwd": parent.path.path,
        ], projectID: parent.id)
        try await env.postHook([
            "session_id": "sess-child",
            "hook_event_name": "SessionStart",
            "cwd": child.path.path,
        ], projectID: child.id)

        try await env.sink.waitForEvents(2)
        let events = env.sink.events
        // Each session's .started must land on its own project — before the
        // fix the shared cwd routed both to whichever spawned last.
        #expect(events.contains { $0.projectID == parent.id && $0.event == .started })
        #expect(events.contains { $0.projectID == child.id && $0.event == .started })
    }

    @Test("POST without the bearer token is rejected and never reaches the sink")
    func unauthorizedPostIsDropped() async throws {
        let env = try await IntegrationEnvironment.start(port: 51793)
        defer { env.teardown() }

        let project = env.makeProject(cwdName: "sf-int-\(UUID().uuidString)")
        _ = env.adapter.prepareSpawn(project: project)

        let status = try await env.postHook(
            [
                "session_id": "sess-anon",
                "hook_event_name": "SessionStart",
                "cwd": project.path.path,
            ],
            projectID: project.id,
            sendAuthHeader: false
        )
        #expect(status == 401)

        // Give the listener a beat in case it would (incorrectly) dispatch.
        try await Task.sleep(for: .milliseconds(100))
        #expect(env.sink.events.isEmpty)
    }
}

// MARK: - Helpers

@MainActor
private struct IntegrationEnvironment {
    let adapter: ClaudeCodeAdapter
    let sink: RecordingSink
    let port: UInt16
    let token: String
    let settingsURL: URL

    static func start(port: UInt16) async throws -> IntegrationEnvironment {
        let token = "test-token-\(UUID().uuidString)"
        let settingsURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("sandfest-int-\(UUID().uuidString).json")
        let adapter = ClaudeCodeAdapter(
            port: port,
            tokenStore: InMemoryTokenStore(token: token),
            settingsManager: SettingsJSONManager(fileURL: settingsURL)
        )
        let sink = RecordingSink()
        try await adapter.start(eventSink: sink)
        return IntegrationEnvironment(
            adapter: adapter,
            sink: sink,
            port: port,
            token: token,
            settingsURL: settingsURL
        )
    }

    func makeProject(cwdName: String) -> Project {
        // Pass `isDirectory: true` so the URL is derived purely from the string,
        // not the filesystem. The bare `appendingPathComponent(_:)` probes disk
        // and appends a trailing slash once the directory exists — so calling
        // this twice for the same cwd (the shared-cwd case) would yield URLs
        // that differ only by that slash and compare unequal.
        let cwd = FileManager.default.temporaryDirectory
            .appendingPathComponent(cwdName, isDirectory: true)
        try? FileManager.default.createDirectory(at: cwd, withIntermediateDirectories: true)
        return Project(name: "Integration", path: cwd)
    }

    @discardableResult
    func postHook(
        _ body: [String: Any],
        projectID: Project.ID? = nil,
        sendAuthHeader: Bool = true
    ) async throws -> Int {
        let payload = try JSONSerialization.data(withJSONObject: body)
        var request = URLRequest(
            url: URL(string: "http://127.0.0.1:\(port)/event?source=sand-festival")!
        )
        request.httpMethod = "POST"
        request.httpBody = payload
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if sendAuthHeader {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        // Mirrors the spawn-injected header the real hook command forwards;
        // SessionStart routing binds on this rather than the cwd.
        if let projectID {
            request.setValue(
                projectID.uuidString,
                forHTTPHeaderField: HookEntryFactory.projectHeaderName
            )
        }
        let (_, response) = try await URLSession.shared.data(for: request)
        return (response as? HTTPURLResponse)?.statusCode ?? -1
    }

    func teardown() {
        Task { [adapter] in await adapter.stop() }
        try? FileManager.default.removeItem(at: settingsURL)
    }
}

private struct InMemoryTokenStore: TokenStore {
    let token: String
    func loadOrCreate() throws -> String { token }
}

@MainActor
private final class RecordingSink: AgentEventSink {
    private(set) var events: [(projectID: Project.ID, event: AgentEvent)] = []

    func report(projectID: Project.ID, event: AgentEvent) {
        events.append((projectID, event))
    }

    func drainEvents() { events.removeAll() }

    func waitForEvents(
        _ count: Int,
        timeout: Duration = .seconds(2)
    ) async throws {
        try await wait(timeout: timeout) { self.events.count >= count }
    }

    private func wait(
        timeout: Duration,
        until condition: @MainActor () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while !condition() {
            if ContinuousClock.now >= deadline {
                throw IntegrationTestError.timedOut
            }
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}

private enum IntegrationTestError: Error { case timedOut }
