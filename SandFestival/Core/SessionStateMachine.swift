import Foundation

/// Pure state machine: maps `(currentState, event) → nextState`. Lives
/// separately from `Session` so it can be tested without spinning up a
/// process.
enum SessionStateMachine {
    static func next(from current: SessionState, event: AgentEvent) -> SessionState {
        // .stopped is a terminal sink from any state.
        if case .stopped = event { return .stopped }

        // `.sessionRestarted` drives the same transitions as `.started`; it
        // exists as a distinct case so `Session.apply` can react to it (by
        // clearing the stale terminal title) without the state machine
        // needing to know about that side effect.
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
