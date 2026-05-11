import SwiftUI

struct StatusDot: View {
    let state: SessionState

    var body: some View {
        Image(systemName: symbolName)
            .font(.system(size: 9))
            .foregroundStyle(strokeOrFill)
            .symbolEffect(.pulse, options: .repeating, isActive: state.needsAttention)
            .frame(width: 12, height: 12)
            .accessibilityLabel(state.displayLabel)
    }

    private var symbolName: String {
        state == .stopped ? "circle" : "circle.fill"
    }

    private var strokeOrFill: Color {
        state == .stopped ? Color.secondary : state.indicatorColor
    }
}
