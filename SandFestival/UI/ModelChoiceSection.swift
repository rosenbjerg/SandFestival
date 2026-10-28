import SwiftUI

struct ModelChoiceSection: View {
    let title: String
    let pickerLabel: String
    @Binding var choice: ModelChoice
    let agentModelName: String?
    let offLabel: String
    let description: String
    let withoutModel: String

    var body: some View {
        Section(title) {
            Picker(pickerLabel, selection: $choice) {
                ForEach(choices) { choice in
                    Text(label(for: choice))
                        .tag(choice)
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

    private var choices: [ModelChoice] {
        ModelChoice.allCases.filter { $0 != .agentModel || agentModelName != nil }
    }

    private func label(for choice: ModelChoice) -> String {
        switch choice {
        case .automatic:
            String(localized: "preferences.model_choice.automatic")
        case .onDevice:
            String(localized: "preferences.model_choice.on_device")
        case .agentModel:
            agentModelName ?? ""
        case .off:
            offLabel
        }
    }

    private var status: String? {
        guard let reason = OnDeviceModel.unavailableReason else { return nil }
        switch choice.source(onDeviceAvailable: false, agentModelAvailable: agentModelName != nil) {
        case .agentModel where choice == .automatic:
            return reason + " " + String(
                format: String(localized: "preferences.model_choice.fallback.agent"),
                agentModelName ?? ""
            )
        case nil where choice != .off:
            return reason + " " + withoutModel
        default:
            return nil
        }
    }
}
