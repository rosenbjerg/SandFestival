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

            Section(String(localized: "preferences.dictation.cleanup.section")) {
                Picker(
                    String(localized: "preferences.dictation.cleanup.label"),
                    selection: $preferences.cleanup
                ) {
                    ForEach(choices) { cleanup in
                        Text(label(for: cleanup))
                            .tag(cleanup)
                    }
                }
                .pickerStyle(.radioGroup)

                Text(description)
                    .interfaceFont(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let status {
                    Label(status, systemImage: "info.circle")
                        .interfaceFont(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
    }

    private var choices: [TranscriptCleanup] {
        TranscriptCleanup.allCases.filter { $0 != .agentModel || agentRefinement != nil }
    }

    private func label(for cleanup: TranscriptCleanup) -> String {
        switch cleanup {
        case .automatic:
            String(localized: "preferences.dictation.cleanup.automatic")
        case .onDevice:
            String(localized: "preferences.dictation.cleanup.on_device")
        case .agentModel:
            agentRefinement?.name ?? ""
        case .off:
            String(localized: "preferences.dictation.cleanup.off")
        }
    }

    private var description: String {
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

    private var status: String? {
        guard let reason = OnDeviceTranscriptRefiner.unavailableReason else { return nil }
        switch preferences.cleanup.source(onDeviceAvailable: false, agentModelAvailable: agentRefinement != nil) {
        case .agentModel where preferences.cleanup == .automatic:
            return reason + " " + String(
                format: String(localized: "preferences.dictation.cleanup.fallback.agent"),
                agentRefinement?.name ?? ""
            )
        case nil where preferences.cleanup != .off:
            return reason + " " + String(localized: "preferences.dictation.cleanup.fallback.raw")
        default:
            return nil
        }
    }
}

#Preview {
    DictationPreferencesView(preferences: DictationPreferences(), agentRefinement: nil)
}
