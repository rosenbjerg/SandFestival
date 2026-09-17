import Foundation

enum AttentionEvent: String, CaseIterable, Identifiable, Sendable {
    case permissionRequested
    case inputRequested
    case blockedByAutoMode
    case errored
    case finishedOutputting

    var id: String { rawValue }
}

extension AttentionEvent {
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
            // Only from .working: .starting → .idle would notify on every launch.
            if case .working = old { return .finishedOutputting }
            return nil
        case .starting, .working, .stopped:
            return nil
        }
    }
}
