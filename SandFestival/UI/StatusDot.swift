import SwiftUI

struct StatusDot: View {
    let state: SessionState

    var body: some View {
        Group {
            if state == .stopped {
                Circle()
                    .strokeBorder(Color.secondary, lineWidth: 1.5)
            } else {
                Circle()
                    .fill(state.indicatorColor)
            }
        }
        .frame(width: 9, height: 9)
        .accessibilityLabel(state.accessibilityLabel)
    }
}

private extension SessionState {
    var accessibilityLabel: String {
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
}
