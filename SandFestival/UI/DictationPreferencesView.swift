import SwiftUI

struct DictationPreferencesView: View {
    @Bindable var preferences: DictationPreferences
    let agentRefinement: AgentTranscriptRefinement?

    var body: some View {
        Form {
            Section(String(localized: "preferences.dictation.listening.section")) {
                Slider(
                    value: $preferences.silenceTimeout,
                    in: DictationEndpointer.Configuration.silenceTimeoutRange,
                    step: 0.5
                ) {
                    Text(String(
                        format: String(localized: "preferences.dictation.silence_timeout.label"),
                        preferences.silenceTimeout
                    ))
                }

                Text(String(localized: "preferences.dictation.silence_timeout.description"))
                    .interfaceFont(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section(String(localized: "preferences.dictation.paste.section")) {
                Toggle(
                    String(localized: "preferences.dictation.submit_after_paste.label"),
                    isOn: $preferences.submitsAfterPaste
                )

                Text(String(localized: "preferences.dictation.submit_after_paste.description"))
                    .interfaceFont(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Toggle(
                    String(localized: "preferences.dictation.submit_while_working.label"),
                    isOn: $preferences.submitsWhileWorking
                )
                .disabled(!preferences.submitsAfterPaste)

                Text(String(localized: "preferences.dictation.submit_while_working.description"))
                    .interfaceFont(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ModelChoiceSection(
                title: String(localized: "preferences.dictation.cleanup.section"),
                pickerLabel: String(localized: "preferences.dictation.cleanup.label"),
                choice: $preferences.cleanup,
                agentModelName: agentRefinement?.name,
                offLabel: String(localized: "preferences.dictation.cleanup.off"),
                description: cleanupDescription,
                withoutModel: String(localized: "preferences.dictation.cleanup.fallback.raw")
            )
        }
        .formStyle(.grouped)
        .frame(width: 480)
    }

    private var cleanupDescription: String {
        switch preferences.cleanup {
        case .automatic:
            if let agentRefinement {
                String(
                    format: String(localized: "preferences.dictation.cleanup.automatic.description.agent"),
                    agentRefinement.name
                )
            } else {
                String(localized: "preferences.dictation.cleanup.automatic.description")
            }
        case .onDevice:
            String(localized: "preferences.dictation.cleanup.on_device.description")
        case .agentModel:
            agentRefinement?.description ?? ""
        case .off:
            String(localized: "preferences.dictation.cleanup.off.description")
        }
    }
}

#Preview {
    DictationPreferencesView(preferences: DictationPreferences(), agentRefinement: nil)
}
