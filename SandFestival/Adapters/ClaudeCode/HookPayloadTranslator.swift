import Foundation

enum HookPayloadTranslator {
    static let askUserQuestionTool = "AskUserQuestion"

    static func translate(_ payload: HookPayload) -> AgentEvent? {
        switch payload.hookEventName {
        case HookEvent.sessionStart.rawValue:
            return .started
        case HookEvent.userPromptSubmit.rawValue:
            return .working
        case HookEvent.preToolUse.rawValue:
            return preToolUseEvent(toolName: payload.toolName)
        case HookEvent.permissionRequest.rawValue:
            return .waitingForPermission
        case HookEvent.postToolUse.rawValue:
            if payload.toolName == Self.askUserQuestionTool { return .working }
            return .toolCompleted
        case HookEvent.postToolUseFailure.rawValue:
            return .toolCompleted
        case HookEvent.notification.rawValue:
            return notificationEvent(type: payload.notificationType, message: payload.notificationMessage)
        case HookEvent.stop.rawValue, HookEvent.stopFailure.rawValue:
            return .idle
        case HookEvent.sessionEnd.rawValue:
            // Not .stopped: SessionEnd also fires for /clear and /resume over a live process.
            return nil
        default:
            return nil
        }
    }

    private static func preToolUseEvent(toolName: String?) -> AgentEvent? {
        guard toolName == Self.askUserQuestionTool else { return nil }
        return .waitingForInput
    }

    private static func notificationEvent(type: String?, message: String?) -> AgentEvent? {
        switch type {
        case "permission_prompt": return .waitingForPermission
        case "idle_prompt": return .waitingForInput
        case .some: return nil
        case nil: return legacyNotificationEvent(message: message)
        }
    }

    private static func legacyNotificationEvent(message: String?) -> AgentEvent? {
        let normalized = (message ?? "").lowercased()
        if normalized.contains("permission") { return .waitingForPermission }
        if normalized.contains("waiting for") || normalized.contains("idle") {
            return .waitingForInput
        }
        return nil
    }
}
