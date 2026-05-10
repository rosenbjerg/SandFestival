import SwiftUI

struct StatusDot: View {
    let state: SessionState

    var body: some View {
        Image(systemName: symbolName)
            .font(.system(size: 9))
            .foregroundStyle(strokeOrFill)
            .symbolEffect(.pulse, options: .repeating, isActive: state.needsAttention)
            .frame(width: 12, height: 12)
            .accessibilityLabel(state.accessibilityLabel)
    }

    private var symbolName: String {
        state == .stopped ? "circle" : "circle.fill"
    }

    private var strokeOrFill: Color {
        state == .stopped ? Color.secondary : state.indicatorColor
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
