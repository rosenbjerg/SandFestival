import Foundation
import Testing
@testable import SandFestival

@Suite("HookPayloadDecoder")
struct HookPayloadDecoderTests {

    @Test("decodes a SessionStart payload with all expected fields")
    func decodesSessionStart() throws {
        let json = """
        {
          "session_id": "sess-1",
          "hook_event_name": "SessionStart",
          "cwd": "/tmp/project",
          "source": "startup"
        }
        """
        let payload = try #require(HookPayloadDecoder.decode(Data(json.utf8)))
        #expect(payload.sessionID == "sess-1")
        #expect(payload.hookEventName == "SessionStart")
        #expect(payload.cwd?.path == "/tmp/project")
    }

    @Test("decodes the final assistant message from a Stop payload")
    func decodesLastAssistantMessage() throws {
        let json = """
        {
          "session_id": "sess-1",
          "hook_event_name": "Stop",
          "stop_hook_active": false,
          "last_assistant_message": "Fixed the race; all tests pass."
        }
        """
        let payload = try #require(HookPayloadDecoder.decode(Data(json.utf8)))
        #expect(payload.lastAssistantMessage == "Fixed the race; all tests pass.")
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
    func capturesNotificationMessage() throws {
        let json = """
        {
          "session_id": "sess-2",
          "hook_event_name": "Notification",
          "message": "Claude needs your permission to use Bash"
        }
        """
        let payload = try #require(HookPayloadDecoder.decode(Data(json.utf8)))
        #expect(payload.notificationMessage == "Claude needs your permission to use Bash")
    }

    @Test("captures notification_type")
    func capturesNotificationType() throws {
        let json = """
        {
          "session_id": "sess-2",
          "hook_event_name": "Notification",
          "message": "Claude needs your permission",
          "notification_type": "permission_prompt"
        }
        """
        let payload = try #require(HookPayloadDecoder.decode(Data(json.utf8)))
        #expect(payload.notificationType == "permission_prompt")
    }

    @Test("captures tool_name on tool-use payloads")
    func capturesToolName() throws {
        let json = """
        {
          "session_id": "sess-3",
          "hook_event_name": "PreToolUse",
          "tool_name": "AskUserQuestion"
        }
        """
        let payload = try #require(HookPayloadDecoder.decode(Data(json.utf8)))
        #expect(payload.toolName == "AskUserQuestion")
    }
}

@MainActor
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

    @Test("PostToolUse for non-AskUserQuestion tools maps to .toolCompleted")
    func postToolUseMapsToToolCompleted() {
        #expect(HookPayloadTranslator.translate(makePayload(event: "PostToolUse")) == .toolCompleted)
        #expect(HookPayloadTranslator.translate(makePayload(event: "PostToolUse", toolName: "Bash")) == .toolCompleted)
    }

    @Test("PostToolUseFailure maps to .toolCompleted — an approved tool can still fail")
    func postToolUseFailureMapsToToolCompleted() {
        let payload = makePayload(event: "PostToolUseFailure", toolName: "Bash")
        #expect(HookPayloadTranslator.translate(payload) == .toolCompleted)
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

    @Test("PermissionRequest maps to .waitingForPermission")
    func permissionRequestMapsToWaitingForPermission() {
        let payload = makePayload(event: "PermissionRequest", toolName: "Bash")
        #expect(HookPayloadTranslator.translate(payload) == .waitingForPermission)
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

    @Test("StopFailure maps to .idle — an API error ends the turn without a Stop")
    func stopFailureMapsToIdle() {
        #expect(HookPayloadTranslator.translate(makePayload(event: "StopFailure")) == .idle)
    }

    @Test("SessionEnd yields no event — OS process termination is the authoritative .stopped signal")
    func sessionEndYieldsNil() {
        #expect(HookPayloadTranslator.translate(makePayload(event: "SessionEnd")) == nil)
    }

    @Test("Notification of type permission_prompt maps to .waitingForPermission")
    func notificationPermissionTypeMapsToWaitingForPermission() {
        let payload = makePayload(event: "Notification", message: "Claude needs your permission", notificationType: "permission_prompt")
        #expect(HookPayloadTranslator.translate(payload) == .waitingForPermission)
    }

    @Test("Notification of type idle_prompt maps to .waitingForInput")
    func notificationIdleTypeMapsToWaitingForInput() {
        let payload = makePayload(event: "Notification", message: "Claude is waiting for your input", notificationType: "idle_prompt")
        #expect(HookPayloadTranslator.translate(payload) == .waitingForInput)
    }

    @Test("Notification of another type yields no event, whatever its message says")
    func notificationOtherTypeIgnoresMessage() {
        let payload = makePayload(event: "Notification", message: "Login permission granted", notificationType: "auth_success")
        #expect(HookPayloadTranslator.translate(payload) == nil)
    }

    @Test("Notification without a type falls back to permission language")
    func notificationLegacyPermissionMapsToWaitingForPermission() {
        let payload = makePayload(event: "Notification", message: "Claude needs your permission to use Bash")
        #expect(HookPayloadTranslator.translate(payload) == .waitingForPermission)
    }

    @Test("Notification without a type falls back to idle language")
    func notificationLegacyIdleMapsToWaitingForInput() {
        let payload = makePayload(event: "Notification", message: "Claude is waiting for your input")
        #expect(HookPayloadTranslator.translate(payload) == .waitingForInput)
    }

    @Test("Notification without a type and with neutral text yields no event")
    func notificationLegacyOtherYieldsNil() {
        let payload = makePayload(event: "Notification", message: "Something else")
        #expect(HookPayloadTranslator.translate(payload) == nil)
    }

    @Test("unknown hook event names yield no event")
    func unknownHookEventsYieldNil() {
        #expect(HookPayloadTranslator.translate(makePayload(event: "SubagentStop")) == nil)
        #expect(HookPayloadTranslator.translate(makePayload(event: "")) == nil)
    }

    private func makePayload(
        event: String,
        message: String? = nil,
        notificationType: String? = nil,
        toolName: String? = nil
    ) -> HookPayload {
        HookPayload(
            sessionID: "sess",
            hookEventName: event,
            cwd: URL(fileURLWithPath: "/tmp"),
            notificationMessage: message,
            notificationType: notificationType,
            toolName: toolName,
            lastAssistantMessage: nil
        )
    }
}

@MainActor
@Suite("SessionBindingStore")
struct SessionBindingStoreTests {

    @Test("SessionStart binds session_id to its spawning project")
    func bindingMatchesByProjectID() {
        let store = SessionBindingStore()
        let projectID = UUID()

        store.registerPendingSpawn(projectID: projectID)
        let resolved = store.bindOnSessionStart(sessionID: "sess-1", projectID: projectID)

        #expect(resolved == .freshSpawn(projectID))
        #expect(store.projectID(forSession: "sess-1") == projectID)
    }

    @Test("subsequent events route by session_id")
    func subsequentEventsRouteBySessionID() {
        let store = SessionBindingStore()
        let projectID = UUID()

        store.registerPendingSpawn(projectID: projectID)
        store.bindOnSessionStart(sessionID: "sess-1", projectID: projectID)

        #expect(store.projectID(forSession: "sess-1") == projectID)
    }

    @Test("SessionStart for a project that never spawned resolves to nil")
    func unknownProjectResolvesToNil() {
        let store = SessionBindingStore()
        store.registerPendingSpawn(projectID: UUID())
        let resolved = store.bindOnSessionStart(
            sessionID: "sess-1",
            projectID: UUID()
        )
        #expect(resolved == nil)
    }

    @Test("two projects sharing a cwd bind to their own ids, not each other's")
    func sharedCwdProjectsDoNotCollide() {
        let store = SessionBindingStore()
        let parent = UUID()
        let child = UUID()

        store.registerPendingSpawn(projectID: parent)
        store.registerPendingSpawn(projectID: child)

        #expect(store.bindOnSessionStart(sessionID: "sess-parent", projectID: parent) == .freshSpawn(parent))
        #expect(store.bindOnSessionStart(sessionID: "sess-child", projectID: child) == .freshSpawn(child))
        #expect(store.projectID(forSession: "sess-parent") == parent)
        #expect(store.projectID(forSession: "sess-child") == child)
    }

    @Test("unbind clears a specific session_id")
    func unbindClearsSession() {
        let store = SessionBindingStore()
        let projectID = UUID()

        store.registerPendingSpawn(projectID: projectID)
        store.bindOnSessionStart(sessionID: "sess-1", projectID: projectID)
        store.unbind(sessionID: "sess-1")

        #expect(store.projectID(forSession: "sess-1") == nil)
    }

    @Test("unbindAll clears every session for a project")
    func unbindAllClearsProject() {
        let store = SessionBindingStore()
        let projectID = UUID()

        store.registerPendingSpawn(projectID: projectID)
        store.bindOnSessionStart(sessionID: "sess-A", projectID: projectID)
        store.bindOnSessionStart(sessionID: "sess-B", projectID: projectID)

        store.unbindAll(projectID: projectID)

        #expect(store.projectID(forSession: "sess-A") == nil)
        #expect(store.projectID(forSession: "sess-B") == nil)
    }

    @Test("a second SessionStart for the same project rebinds while it's still live (e.g. /resume, /clear)")
    func secondSessionStartRebindsLiveProject() {
        let store = SessionBindingStore()
        let projectID = UUID()

        store.registerPendingSpawn(projectID: projectID)
        let first = store.bindOnSessionStart(sessionID: "sess-1", projectID: projectID)
        #expect(first == .freshSpawn(projectID))
        let second = store.bindOnSessionStart(sessionID: "sess-2", projectID: projectID)
        #expect(second == .rebound(projectID))
        #expect(store.projectID(forSession: "sess-2") == projectID)
    }

    @Test("a SessionStart for a project that has been unbound is dropped")
    func sessionStartAfterUnbindAllIsDropped() {
        let store = SessionBindingStore()
        let projectID = UUID()

        store.registerPendingSpawn(projectID: projectID)
        _ = store.bindOnSessionStart(sessionID: "sess-1", projectID: projectID)
        store.unbindAll(projectID: projectID)
        let stray = store.bindOnSessionStart(sessionID: "sess-stray", projectID: projectID)
        #expect(stray == nil)
    }
}
