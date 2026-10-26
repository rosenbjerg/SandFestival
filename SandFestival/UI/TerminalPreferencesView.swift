import SwiftUI

struct TerminalPreferencesView: View {
    let manager: SessionManager

    @State private var draft: Int = SessionManager.defaultScrollback
    @State private var useMetalDraft: Bool = false
    @State private var familyDraft: String = ""
    @State private var sizeDraft: Double = Double(SessionManager.defaultFontSize)
    @State private var blocksClipboardDraft: Bool = true

    var body: some View {
        Form {
            Section(String(localized: "preferences.terminal.font.section")) {
                Picker(String(localized: "preferences.terminal.font.family.label"), selection: $familyDraft) {
                    Text(String(localized: "preferences.terminal.font.family.system"))
                        .tag("")
                    Divider()
                    ForEach(TerminalFont.monospacedFamilies, id: \.self) { family in
                        Text(family)
                            .font(.custom(family, size: 13))
                            .tag(family)
                    }
                }

                Stepper(
                    value: $sizeDraft,
                    in: Double(SessionManager.minFontSize)...Double(SessionManager.maxFontSize),
                    step: 1
                ) {
                    LabeledContent(String(localized: "preferences.terminal.font.size.label")) {
                        Text(formattedSize(sizeDraft))
                            .monospacedDigit()
                    }
                }
            }

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
                    .interfaceFont(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section(String(localized: "preferences.terminal.metal.section")) {
                Toggle(String(localized: "preferences.terminal.metal.label"), isOn: $useMetalDraft)

                Text(String(localized: "preferences.terminal.metal.description"))
                    .interfaceFont(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section(String(localized: "preferences.terminal.clipboard.section")) {
                Toggle(String(localized: "preferences.terminal.clipboard.label"), isOn: $blocksClipboardDraft)

                Text(String(localized: "preferences.terminal.clipboard.description"))
                    .interfaceFont(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .onAppear {
            draft = manager.terminalScrollback
            useMetalDraft = manager.useMetalRenderer
            familyDraft = TerminalFont.isAvailable(family: manager.terminalFontFamily)
                ? manager.terminalFontFamily
                : ""
            sizeDraft = Double(manager.terminalFontSize)
            blocksClipboardDraft = manager.blocksAgentClipboard
        }
        .onChange(of: draft) { _, newValue in
            manager.applyTerminalScrollback(newValue)
        }
        .onChange(of: useMetalDraft) { _, newValue in
            manager.applyMetalRenderer(newValue)
        }
        .onChange(of: familyDraft) { _, newValue in
            manager.applyTerminalFontFamily(newValue)
        }
        .onChange(of: sizeDraft) { _, newValue in
            manager.applyTerminalFontSize(CGFloat(newValue))
        }
        .onChange(of: blocksClipboardDraft) { _, newValue in
            manager.applyAgentClipboardBlocking(newValue)
        }
    }

    private func formattedSize(_ value: Double) -> String {
        String(format: String(localized: "preferences.terminal.font.size.unit"), Int(value))
    }

    private func formattedLines(_ value: Int) -> String {
        let number = NumberFormatter.localizedString(from: NSNumber(value: value), number: .decimal)
        return String(format: String(localized: "preferences.terminal.scrollback.unit"), number)
    }
}

#Preview {
    TerminalPreferencesView(manager: SessionManager())
}
