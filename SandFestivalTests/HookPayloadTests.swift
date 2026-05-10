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
          "permission_mode": "default",
          "source": "startup"
        }
        """
        let payload = try? #require(HookPayloadDecoder.decode(Data(json.utf8)))
        #expect(payload?.sessionID == "sess-1")
        #expect(payload?.hookEventName == "SessionStart")
        #expect(payload?.cwd?.path == "/tmp/project")
        #expect(payload?.permissionMode == "default")
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

    @Test("PostToolUse maps to .heartbeat")
    func postToolUseMapsToHeartbeat() {
        #expect(HookPayloadTranslator.translate(makePayload(event: "PostToolUse")) == .heartbeat)
    }

    @Test("Stop maps to .idle")
    func stopMapsToIdle() {
        #expect(HookPayloadTranslator.translate(makePayload(event: "Stop")) == .idle)
    }

    @Test("SessionEnd maps to .stopped")
    func sessionEndMapsToStopped() {
        #expect(HookPayloadTranslator.translate(makePayload(event: "SessionEnd")) == .stopped)
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
        #expect(HookPayloadTranslator.translate(makePayload(event: "PreToolUse")) == nil)
        #expect(HookPayloadTranslator.translate(makePayload(event: "")) == nil)
    }

    private func makePayload(event: String, message: String? = nil) -> HookPayload {
        HookPayload(
            sessionID: "sess",
            hookEventName: event,
            cwd: URL(fileURLWithPath: "/tmp"),
            permissionMode: nil,
            notificationMessage: message,
            stopReason: nil
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

    @Test("pending spawn entries are consumed on first SessionStart")
    func pendingSpawnIsConsumed() {
        let store = SessionBindingStore()
        let projectID = UUID()
        let cwd = URL(fileURLWithPath: "/tmp/repo")

        store.registerPendingSpawn(projectID: projectID, cwd: cwd)
        _ = store.bindOnSessionStart(sessionID: "sess-1", cwd: cwd)
        // A second SessionStart with the same cwd should not re-bind.
        let second = store.bindOnSessionStart(sessionID: "sess-2", cwd: cwd)
        #expect(second == nil)
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
}
