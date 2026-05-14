import Foundation

enum HookPayloadTranslator {
    /// Tool name Claude Code uses when prompting the user with a structured
    /// question. We listen for it on PreToolUse to flip into a "waiting"
    /// state, and on PostToolUse to flip back out once the user answers.
    static let askUserQuestionTool = "AskUserQuestion"

    /// Maps a decoded hook payload to an `AgentEvent`, or `nil` if the event
    /// carries no signal for the state machine.
    static func translate(_ payload: HookPayload) -> AgentEvent? {
        switch payload.hookEventName {
        case HookEvent.sessionStart.rawValue:
            return .started
        case HookEvent.userPromptSubmit.rawValue:
            return .working
        case HookEvent.preToolUse.rawValue:
            return preToolUseEvent(toolName: payload.toolName)
        case HookEvent.postToolUse.rawValue:
            // AskUserQuestion's PostToolUse fires once the user has answered,
            // so emit .working to lift waitingForIdle. Every other tool's
            // PostToolUse carries no state signal — Session.apply already
            // short-circuits same-state events, so dropping the event here
            // is equivalent to the old "heartbeat" no-op.
            if payload.toolName == Self.askUserQuestionTool { return .working }
            return nil
        case HookEvent.notification.rawValue:
            return notificationEvent(message: payload.notificationMessage)
        case HookEvent.stop.rawValue:
            return .idle
        case HookEvent.sessionEnd.rawValue:
            // SessionEnd fires for `/clear` and `/resume` too — the OS process
            // keeps running with a fresh session_id. Process death is detected
            // by the OS-level termination callback in `Session`, so don't let
            // this hook drive the state machine to `.stopped` and trigger the
            // "not running" overlay over a live process.
            return nil
        default:
            return nil
        }
    }

    private static func preToolUseEvent(toolName: String?) -> AgentEvent? {
        guard toolName == Self.askUserQuestionTool else { return nil }
        return .waitingForInput
    }

    private static func notificationEvent(message: String?) -> AgentEvent? {
        let normalized = (message ?? "").lowercased()
        if normalized.contains("permission") { return .waitingForPermission }
        if normalized.contains("waiting for") || normalized.contains("idle") {
            return .waitingForInput
        }
        return nil
    }
}
