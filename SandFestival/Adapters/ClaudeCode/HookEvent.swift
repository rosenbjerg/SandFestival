import Foundation

enum HookEvent: String, CaseIterable, Sendable {
    case sessionStart = "SessionStart"
    case userPromptSubmit = "UserPromptSubmit"
    case preToolUse = "PreToolUse"
    case postToolUse = "PostToolUse"
    case notification = "Notification"
    case stop = "Stop"
    case sessionEnd = "SessionEnd"
}

extension HookEvent {
    var matcher: String {
        switch self {
        case .preToolUse: return "AskUserQuestion"
        default: return ""
        }
    }
}
