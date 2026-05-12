import SwiftUI

struct TerminalPreferencesView: View {
    let manager: SessionManager

    @State private var draft: Int = SessionManager.defaultScrollback

    var body: some View {
        Form {
            Section(String(localized: "preferences.terminal.scrollback.section")) {
                Stepper(
                    value: $draft,
                    in: SessionManager.minScrollback...SessionManager.maxScrollback,
                    step: 500
                ) {
                    LabeledContent(String(localized: "preferences.terminal.scrollback.label")) {
                        Text(formattedLines(draft))
                            .monospacedDigit()
                    }
                }

                Text(String(format: String(localized: "preferences.terminal.scrollback.description"),
                            SessionManager.minScrollback,
                            SessionManager.maxScrollback))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .onAppear {
            draft = manager.terminalScrollback
        }
        .onChange(of: draft) { _, newValue in
            manager.applyTerminalScrollback(newValue)
        }
    }

    private func formattedLines(_ value: Int) -> String {
        let number = NumberFormatter.localizedString(from: NSNumber(value: value), number: .decimal)
        return String(format: String(localized: "preferences.terminal.scrollback.unit"), number)
    }
}

#Preview {
    TerminalPreferencesView(manager: SessionManager())
}
