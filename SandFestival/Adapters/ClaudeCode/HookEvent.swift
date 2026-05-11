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
    /// Matcher value installed alongside this hook in `~/.claude/settings.json`.
    /// Empty matches every invocation; PreToolUse is scoped to AskUserQuestion
    /// so the curl only fires when Claude actually asks the user a question
    /// rather than once per tool call.
    var matcher: String {
        switch self {
        case .preToolUse: return "AskUserQuestion"
        default: return ""
        }
    }
}
