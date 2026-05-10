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
    var needsAttention: Bool {
        switch self {
        case .waitingForPermission, .waitingForIdle, .blockedByAutoMode, .errored:
            return true
        case .starting, .idle, .working, .stopped:
            return false
        }
    }

    var isRunning: Bool {
        switch self {
        case .stopped:
            return false
        case .starting, .idle, .working, .waitingForPermission, .waitingForIdle, .blockedByAutoMode, .errored:
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
