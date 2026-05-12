import Foundation

/// Discrete categories of session-state change the user can opt into being
/// alerted about. Each value maps to at most one transition kind, so the
/// per-event preference set can gate notifications and dock bounce without
/// the notifier having to reason about raw state pairs.
enum AttentionEvent: String, CaseIterable, Identifiable, Sendable {
    case permissionRequested
    case inputRequested
    case blockedByAutoMode
    case errored
    case finishedOutputting
    case stopped

    var id: String { rawValue }
}

extension AttentionEvent {
    /// Maps a state transition to the alertable event it represents, if
    /// any. `Session.transition(to:)` already filters out no-op
    /// transitions, so callers can assume `old != new`.
    ///
    /// `.working → .idle` is the "Claude finished its turn" signal. Other
    /// paths into `.idle` (e.g. `.starting → .idle` settle, or recovery
    /// from an attention state) aren't surfaced — the user either just
    /// launched the session or just resolved attention themselves, so a
    /// notification would be noise.
    static func from(transition old: SessionState, to new: SessionState) -> AttentionEvent? {
        switch new {
        case .waitingForPermission:
            return .permissionRequested
        case .waitingForIdle:
            return .inputRequested
        case .blockedByAutoMode:
            return .blockedByAutoMode
        case .errored:
            return .errored
        case .idle:
            if case .working = old { return .finishedOutputting }
            return nil
        case .stopped:
            return .stopped
        case .starting, .working:
            return nil
        }
    }
}
