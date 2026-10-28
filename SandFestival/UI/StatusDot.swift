import SwiftUI

struct StatusDot: View {
    let state: SessionState
    var kind: Kind = .standalone

    enum Kind {
        case standalone
        case worktree
        case duplicate

        init(project: Project) {
            if project.worktreeInfo != nil {
                self = .worktree
            } else if project.parentProjectID != nil {
                self = .duplicate
            } else {
                self = .standalone
            }
        }
    }

    var body: some View {
        Image(systemName: symbolName)
            .font(.system(size: pointSize, weight: kind == .standalone ? .regular : .medium))
            .foregroundStyle(style)
            .symbolEffect(.pulse, options: .repeating, isActive: state.needsAttention)
            .frame(width: 12, height: 12)
            .accessibilityLabel(accessibilityLabel)
            .help(kindHelp)
    }

    private var symbolName: String {
        switch kind {
        case .standalone: state == .stopped ? "circle" : "circle.fill"
        case .worktree: "arrow.trianglehead.branch"
        case .duplicate: "square.on.square"
        }
    }

    private var pointSize: CGFloat {
        kind == .worktree ? 10 : 9
    }

    private var style: AnyShapeStyle {
        if state == .stopped {
            return AnyShapeStyle(.secondary)
        }
        if kind != .standalone, state == .idle || state == .starting {
            return AnyShapeStyle(.primary)
        }
        return AnyShapeStyle(state.indicatorColor)
    }

    private var accessibilityLabel: String {
        switch kind {
        case .standalone:
            state.displayLabel
        case .worktree:
            String(format: String(localized: "status_dot.worktree.accessibility"), state.displayLabel)
        case .duplicate:
            String(format: String(localized: "status_dot.duplicate.accessibility"), state.displayLabel)
        }
    }

    private var kindHelp: String {
        switch kind {
        case .standalone: ""
        case .worktree: String(localized: "status_dot.worktree.help")
        case .duplicate: String(localized: "status_dot.duplicate.help")
        }
    }
}
