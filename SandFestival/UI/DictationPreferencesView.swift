import SwiftUI

struct DictationPreferencesView: View {
    @Bindable var preferences: DictationPreferences

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

            Section(String(localized: "preferences.dictation.cleanup.section")) {
                Picker(
                    String(localized: "preferences.dictation.cleanup.label"),
                    selection: $preferences.cleanup
                ) {
                    ForEach(TranscriptCleanup.allCases) { cleanup in
                        Text(cleanup.displayLabel)
                            .tag(cleanup)
                    }
                }
                .pickerStyle(.radioGroup)

                Text(description)
                    .interfaceFont(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if preferences.cleanup == .onDevice, let reason = OnDeviceTranscriptRefiner.unavailableReason {
                    Label(reason, systemImage: "exclamationmark.triangle.fill")
                        .interfaceFont(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
    }

    private var description: String {
        switch preferences.cleanup {
        case .off:
            String(localized: "preferences.dictation.cleanup.off.description")
        case .onDevice:
            String(localized: "preferences.dictation.cleanup.on_device.description")
        case .claudeHaiku:
            String(localized: "preferences.dictation.cleanup.claude_haiku.description")
        }
    }
}

#Preview {
    DictationPreferencesView(preferences: DictationPreferences())
}
