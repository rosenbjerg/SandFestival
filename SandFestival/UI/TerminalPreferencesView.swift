import SwiftUI

struct TerminalPreferencesView: View {
    let manager: SessionManager

    @State private var draft: Int = SessionManager.defaultScrollback
    @State private var useMetalDraft: Bool = false

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

            Section(String(localized: "preferences.terminal.metal.section")) {
                Toggle(String(localized: "preferences.terminal.metal.label"), isOn: $useMetalDraft)

                Text(String(localized: "preferences.terminal.metal.description"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .onAppear {
            draft = manager.terminalScrollback
            useMetalDraft = manager.useMetalRenderer
        }
        .onChange(of: draft) { _, newValue in
            manager.applyTerminalScrollback(newValue)
        }
        .onChange(of: useMetalDraft) { _, newValue in
            manager.applyMetalRenderer(newValue)
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
