import Foundation

enum AgentEvent: Equatable {
    case started
    /// A SessionStart hook for an OS process that's already live — e.g.
    /// Claude Code's `/resume` or `/clear`, which mint a new session_id
    /// without restarting the process. Drives the same state transitions
    /// as `.started`, but also tells `Session` to drop the previous
    /// conversation's terminal title so a stale OSC-set summary doesn't
    /// outlive the conversation it described.
    case sessionRestarted
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
