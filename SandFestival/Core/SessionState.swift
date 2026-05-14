import Foundation
import SwiftUI

enum SessionState: Equatable {
    case starting
    case idle
    case working
    case waitingForPermission
    case waitingForIdle
    case blockedByAutoMode
    case errored(reason: String)
    case stopped
}

extension SessionState {
    /// Short, localized name for the state. Used by the sidebar status
    /// dot's accessibility label and anywhere else the UI needs to say
    /// "what is this session doing right now" in one word.
    var displayLabel: String {
        switch self {
        case .starting: return String(localized: "status.starting")
        case .idle: return String(localized: "status.idle")
        case .working: return String(localized: "status.working")
        case .waitingForPermission: return String(localized: "status.waiting_permission")
        case .waitingForIdle: return String(localized: "status.waiting_idle")
        case .blockedByAutoMode: return String(localized: "status.blocked_auto_mode")
        case .errored: return String(localized: "status.errored")
        case .stopped: return String(localized: "status.stopped")
        }
    }

    var needsAttention: Bool {
        switch self {
        case .waitingForPermission, .waitingForIdle, .blockedByAutoMode, .errored:
            return true
        case .starting, .idle, .working, .stopped:
            return false
        }
    }

    /// True when there's an OS-level process behind the session that the UI
    /// should treat as alive (toolbar shows Stop, no "not running" overlay).
    /// `.errored` joins `.stopped` because the only path to errored today is
    /// `Session.start()` failing to resolve the command — no process was
    /// spawned, so Stop would be a no-op and the overlay should offer Start.
    var isRunning: Bool {
        switch self {
        case .stopped, .errored:
            return false
        case .starting, .idle, .working, .waitingForPermission, .waitingForIdle, .blockedByAutoMode:
            return true
        }
    }

    var indicatorColor: Color {
        switch self {
        case .idle:
            return .secondary
        case .working:
            return .blue
        case .waitingForPermission, .waitingForIdle:
            return .orange
        case .blockedByAutoMode, .errored:
            return .red
        case .stopped:
            return Color.secondary.opacity(0.4)
        case .starting:
            return .secondary
        }
    }
}
