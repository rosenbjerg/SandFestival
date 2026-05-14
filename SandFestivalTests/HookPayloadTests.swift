import Foundation
import Testing
@testable import SandFestival

@Suite("HookPayloadDecoder")
struct HookPayloadDecoderTests {

    @Test("decodes a SessionStart payload with all expected fields")
    func decodesSessionStart() {
        let json = """
        {
          "session_id": "sess-1",
          "hook_event_name": "SessionStart",
          "cwd": "/tmp/project",
          "source": "startup"
        }
        """
        let payload = try? #require(HookPayloadDecoder.decode(Data(json.utf8)))
        #expect(payload?.sessionID == "sess-1")
        #expect(payload?.hookEventName == "SessionStart")
        #expect(payload?.cwd?.path == "/tmp/project")
    }

    @Test("returns nil for malformed JSON")
    func returnsNilForMalformedJSON() {
        #expect(HookPayloadDecoder.decode(Data("{garbage".utf8)) == nil)
    }

    @Test("returns nil when required fields are missing")
    func returnsNilForMissingFields() {
        let missingSessionID = """
        { "hook_event_name": "SessionStart" }
        """
        let missingEventName = """
        { "session_id": "abc" }
        """
        #expect(HookPayloadDecoder.decode(Data(missingSessionID.utf8)) == nil)
        #expect(HookPayloadDecoder.decode(Data(missingEventName.utf8)) == nil)
    }

    @Test("captures Notification message text")
    func capturesNotificationMessage() {
        let json = """
        {
          "session_id": "sess-2",
          "hook_event_name": "Notification",
          "message": "Claude needs your permission to use Bash"
        }
        """
        let payload = try? #require(HookPayloadDecoder.decode(Data(json.utf8)))
        #expect(payload?.notificationMessage == "Claude needs your permission to use Bash")
    }

    @Test("captures tool_name on tool-use payloads")
    func capturesToolName() {
        let json = """
        {
          "session_id": "sess-3",
          "hook_event_name": "PreToolUse",
          "tool_name": "AskUserQuestion"
        }
        """
        let payload = try? #require(HookPayloadDecoder.decode(Data(json.utf8)))
        #expect(payload?.toolName == "AskUserQuestion")
    }
}

@Suite("HookPayloadTranslator")
struct HookPayloadTranslatorTests {

    @Test("SessionStart maps to .started")
    func sessionStartMapsToStarted() {
        let payload = makePayload(event: "SessionStart")
        #expect(HookPayloadTranslator.translate(payload) == .started)
    }

    @Test("UserPromptSubmit maps to .working")
    func userPromptSubmitMapsToWorking() {
        #expect(HookPayloadTranslator.translate(makePayload(event: "UserPromptSubmit")) == .working)
    }

    @Test("PostToolUse for non-AskUserQuestion tools yields no event")
    func postToolUseYieldsNil() {
        // The state machine already short-circuits same-state events, so
        // there's nothing for a generic PostToolUse to do — emit nothing
        // rather than carry a placeholder event through the sink.
        #expect(HookPayloadTranslator.translate(makePayload(event: "PostToolUse")) == nil)
        #expect(HookPayloadTranslator.translate(makePayload(event: "PostToolUse", toolName: "Bash")) == nil)
    }

    @Test("PreToolUse for AskUserQuestion maps to .waitingForInput")
    func preToolUseAskUserQuestionMapsToWaitingForInput() {
        let payload = makePayload(event: "PreToolUse", toolName: "AskUserQuestion")
        #expect(HookPayloadTranslator.translate(payload) == .waitingForInput)
    }

    @Test("PreToolUse for any other tool yields no event")
    func preToolUseOtherToolYieldsNil() {
        #expect(HookPayloadTranslator.translate(makePayload(event: "PreToolUse", toolName: "Bash")) == nil)
        #expect(HookPayloadTranslator.translate(makePayload(event: "PreToolUse", toolName: nil)) == nil)
    }

    @Test("PostToolUse for AskUserQuestion maps to .working (user answered)")
    func postToolUseAskUserQuestionMapsToWorking() {
        let payload = makePayload(event: "PostToolUse", toolName: "AskUserQuestion")
        #expect(HookPayloadTranslator.translate(payload) == .working)
    }

    @Test("Stop maps to .idle")
    func stopMapsToIdle() {
        #expect(HookPayloadTranslator.translate(makePayload(event: "Stop")) == .idle)
    }

    @Test("SessionEnd yields no event — OS process termination is the authoritative .stopped signal")
    func sessionEndYieldsNil() {
        // SessionEnd also fires for /clear and /resume while the process keeps
        // running, so it must not push the state machine into .stopped.
        #expect(HookPayloadTranslator.translate(makePayload(event: "SessionEnd")) == nil)
    }

    @Test("Notification with permission language maps to .waitingForPermission")
    func notificationPermissionMapsToWaitingForPermission() {
        let payload = makePayload(event: "Notification", message: "Claude needs your permission to use Bash")
        #expect(HookPayloadTranslator.translate(payload) == .waitingForPermission)
    }

    @Test("Notification with idle language maps to .waitingForInput")
    func notificationIdleMapsToWaitingForInput() {
        let payload = makePayload(event: "Notification", message: "Claude is waiting for your input")
        #expect(HookPayloadTranslator.translate(payload) == .waitingForInput)
    }

    @Test("Notification with neutral text yields no event")
    func notificationOtherYieldsNil() {
        let payload = makePayload(event: "Notification", message: "Something else")
        #expect(HookPayloadTranslator.translate(payload) == nil)
    }

    @Test("unknown hook event names yield no event")
    func unknownHookEventsYieldNil() {
        #expect(HookPayloadTranslator.translate(makePayload(event: "SubagentStop")) == nil)
        #expect(HookPayloadTranslator.translate(makePayload(event: "")) == nil)
    }

    private func makePayload(event: String, message: String? = nil, toolName: String? = nil) -> HookPayload {
        HookPayload(
            sessionID: "sess",
            hookEventName: event,
            cwd: URL(fileURLWithPath: "/tmp"),
            notificationMessage: message,
            toolName: toolName
        )
    }
}

@MainActor
@Suite("SessionBindingStore")
struct SessionBindingStoreTests {

    @Test("SessionStart binds session_id by matching pending cwd")
    func bindingMatchesByCwd() {
        let store = SessionBindingStore()
        let projectID = UUID()
        let cwd = URL(fileURLWithPath: "/tmp/repo")

        store.registerPendingSpawn(projectID: projectID, cwd: cwd)
        let resolved = store.bindOnSessionStart(sessionID: "sess-1", cwd: cwd)

        #expect(resolved == projectID)
        #expect(store.projectID(forSession: "sess-1") == projectID)
    }

    @Test("subsequent events route by session_id, ignoring cwd")
    func subsequentEventsRouteBySessionID() {
        let store = SessionBindingStore()
        let projectID = UUID()
        let cwd = URL(fileURLWithPath: "/tmp/repo")

        store.registerPendingSpawn(projectID: projectID, cwd: cwd)
        store.bindOnSessionStart(sessionID: "sess-1", cwd: cwd)

        #expect(store.projectID(forSession: "sess-1") == projectID)
    }

    @Test("SessionStart for an unknown cwd resolves to nil")
    func unknownCwdResolvesToNil() {
        let store = SessionBindingStore()
        store.registerPendingSpawn(projectID: UUID(), cwd: URL(fileURLWithPath: "/tmp/a"))
        let resolved = store.bindOnSessionStart(
            sessionID: "sess-1",
            cwd: URL(fileURLWithPath: "/tmp/b")
        )
        #expect(resolved == nil)
    }

    @Test("unbind clears a specific session_id")
    func unbindClearsSession() {
        let store = SessionBindingStore()
        let projectID = UUID()
        let cwd = URL(fileURLWithPath: "/tmp/repo")

        store.registerPendingSpawn(projectID: projectID, cwd: cwd)
        store.bindOnSessionStart(sessionID: "sess-1", cwd: cwd)
        store.unbind(sessionID: "sess-1")

        #expect(store.projectID(forSession: "sess-1") == nil)
    }

    @Test("unbindAll clears every session for a project")
    func unbindAllClearsProject() {
        let store = SessionBindingStore()
        let projectID = UUID()
        let cwdA = URL(fileURLWithPath: "/tmp/a")
        let cwdB = URL(fileURLWithPath: "/tmp/b")

        store.registerPendingSpawn(projectID: projectID, cwd: cwdA)
        store.bindOnSessionStart(sessionID: "sess-A", cwd: cwdA)
        store.registerPendingSpawn(projectID: projectID, cwd: cwdB)
        store.bindOnSessionStart(sessionID: "sess-B", cwd: cwdB)

        store.unbindAll(projectID: projectID)

        #expect(store.projectID(forSession: "sess-A") == nil)
        #expect(store.projectID(forSession: "sess-B") == nil)
    }

    @Test("a second SessionStart for the same cwd rebinds while the project is still live (e.g. /resume, /clear)")
    func secondSessionStartRebindsLiveProject() {
        let store = SessionBindingStore()
        let projectID = UUID()
        let cwd = URL(fileURLWithPath: "/tmp/repo")

        store.registerPendingSpawn(projectID: projectID, cwd: cwd)
        _ = store.bindOnSessionStart(sessionID: "sess-1", cwd: cwd)
        // /resume mints a new session_id without restarting the process. As
        // long as we haven't been told the project is gone, the new session_id
        // must bind to the same project so subsequent events route correctly.
        let second = store.bindOnSessionStart(sessionID: "sess-2", cwd: cwd)
        #expect(second == projectID)
        #expect(store.projectID(forSession: "sess-2") == projectID)
    }

    @Test("a SessionStart for a cwd whose project has been unbound is dropped")
    func sessionStartAfterUnbindAllIsDropped() {
        let store = SessionBindingStore()
        let projectID = UUID()
        let cwd = URL(fileURLWithPath: "/tmp/repo")

        store.registerPendingSpawn(projectID: projectID, cwd: cwd)
        _ = store.bindOnSessionStart(sessionID: "sess-1", cwd: cwd)
        // unbindAll fires on process termination — a stray claude run from the
        // same cwd afterwards (e.g. the user invokes claude by hand) must not
        // attach to the dead session.
        store.unbindAll(projectID: projectID)
        let stray = store.bindOnSessionStart(sessionID: "sess-stray", cwd: cwd)
        #expect(stray == nil)
    }

    @Test("cwd matching is path-normalized")
    func cwdMatchingIsNormalized() {
        let store = SessionBindingStore()
        let projectID = UUID()
        store.registerPendingSpawn(
            projectID: projectID,
            cwd: URL(fileURLWithPath: "/tmp/repo/")
        )
        let resolved = store.bindOnSessionStart(
            sessionID: "sess-1",
            cwd: URL(fileURLWithPath: "/tmp/repo")
        )
        #expect(resolved == projectID)
    }

    @Test("cwd matching resolves through symlinks")
    func cwdMatchingResolvesThroughSymlinks() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory
            .appendingPathComponent("sandfest-symlink-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let real = root.appendingPathComponent("real")
        let link = root.appendingPathComponent("link")
        try fm.createDirectory(at: real, withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: link, withDestinationURL: real)

        let store = SessionBindingStore()
        let projectID = UUID()
        // Register under the symlink path (what the user typed in the editor)…
        store.registerPendingSpawn(projectID: projectID, cwd: link)
        // …and bind under the resolved path (what Claude's cwd hook reports).
        let resolved = store.bindOnSessionStart(sessionID: "sess-1", cwd: real)
        #expect(resolved == projectID)
    }
}
