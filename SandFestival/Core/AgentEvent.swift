import Foundation

enum AgentEvent: Equatable {
    case started
    case working
    case idle
    case waitingForPermission
    case waitingForInput
    case blockedByAutoMode
    case errored(reason: String)
    case stopped
    /// User typed into the session's terminal. Claude Code emits no hook
    /// when the user dismisses an `AskUserQuestion` prompt with Ctrl+C, so
    /// terminal input is our fallback signal that the user has re-engaged.
    /// Only `.waitingForIdle` reacts; every other state ignores it so that
    /// e.g. typing during `.waitingForPermission` doesn't fake a grant.
    case userInteracted
}
