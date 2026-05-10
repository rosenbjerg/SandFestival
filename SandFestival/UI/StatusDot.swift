import SwiftUI

struct StatusDot: View {
    let state: SessionState

    var body: some View {
        Circle()
            .fill(state.indicatorColor)
            .frame(width: 8, height: 8)
            .opacity(state == .stopped ? 0.6 : 1.0)
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
