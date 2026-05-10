import Foundation

enum HookPayloadTranslator {
    /// Maps a decoded hook payload to an `AgentEvent`, or `nil` if the event
    /// carries no signal for the state machine.
    static func translate(_ payload: HookPayload) -> AgentEvent? {
        switch payload.hookEventName {
        case HookEvent.sessionStart.rawValue:
            return .started
        case HookEvent.userPromptSubmit.rawValue:
            return .working
        case HookEvent.postToolUse.rawValue:
            return .heartbeat
        case HookEvent.notification.rawValue:
            return notificationEvent(message: payload.notificationMessage)
        case HookEvent.stop.rawValue:
            return .idle
        case HookEvent.sessionEnd.rawValue:
            return .stopped
        default:
            return nil
        }
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
