import Foundation

enum HookEvent: String, CaseIterable, Sendable {
    case sessionStart = "SessionStart"
    case userPromptSubmit = "UserPromptSubmit"
    case postToolUse = "PostToolUse"
    case notification = "Notification"
    case stop = "Stop"
    case sessionEnd = "SessionEnd"
}
