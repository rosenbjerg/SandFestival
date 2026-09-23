import SwiftUI

struct InterfacePreferencesView: View {
    @Bindable var preferences: InterfacePreferences

    var body: some View {
        Form {
            Section(String(localized: "preferences.interface.text_size.section")) {
                Picker(
                    String(localized: "preferences.interface.text_size.label"),
                    selection: $preferences.textSize
                ) {
                    ForEach(InterfaceTextSize.allCases) { size in
                        Text(size.displayLabel)
                            .tag(size)
                    }
                }
                .pickerStyle(.segmented)

                Text(String(localized: "preferences.interface.text_size.description"))
                    .interfaceFont(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
    }
}

#Preview {
    InterfacePreferencesView(preferences: InterfacePreferences())
}
