import Foundation

enum SessionStateMachine {
    static func next(from current: SessionState, event: AgentEvent) -> SessionState {
        if case .stopped = event { return .stopped }

        switch current {
        case .starting:
            switch event {
            case .started, .sessionRestarted: return .idle
            case .working: return .working
            case .errored(let reason): return .errored(reason: reason)
            default: return current
            }

        case .idle:
            switch event {
            case .working: return .working
            case .errored(let reason): return .errored(reason: reason)
            default: return current
            }

        case .working:
            switch event {
            case .working: return .working
            case .idle: return .idle
            case .waitingForPermission: return .waitingForPermission
            case .waitingForInput: return .waitingForIdle
            case .blockedByAutoMode: return .blockedByAutoMode
            case .errored(let reason): return .errored(reason: reason)
            default: return current
            }

        case .waitingForIdle:
            switch event {
            case .working: return .working
            case .idle, .userInteracted: return .idle
            case .errored(let reason): return .errored(reason: reason)
            default: return current
            }

        case .waitingForPermission, .blockedByAutoMode:
            // No .userInteracted here: typing at a permission prompt isn't a grant.
            switch event {
            case .working: return .working
            case .idle: return .idle
            case .errored(let reason): return .errored(reason: reason)
            default: return current
            }

        case .errored:
            switch event {
            case .working: return .working
            case .started, .sessionRestarted: return .idle
            default: return current
            }

        case .stopped:
            switch event {
            case .started, .sessionRestarted: return .idle
            case .working: return .working
            default: return current
            }
        }
    }
}
