import SwiftUI

struct KeepAwakePreferencesView: View {
    @Bindable var preferences: KeepAwakePreferences

    var body: some View {
        Form {
            Section(String(localized: "preferences.keep_awake.section")) {
                Toggle(
                    String(localized: "preferences.keep_awake.enabled"),
                    isOn: $preferences.isEnabled
                )

                if preferences.isEnabled {
                    Toggle(
                        String(localized: "preferences.keep_awake.only_plugged_in"),
                        isOn: $preferences.onlyWhenPluggedIn
                    )
                }

                Text(String(localized: "preferences.keep_awake.description"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
    }
}

#Preview {
    KeepAwakePreferencesView(preferences: KeepAwakePreferences())
}
