import Foundation

enum InterfaceTextSize: String, CaseIterable, Identifiable, Sendable {
    case small
    case medium
    case large
    case extraLarge

    var id: String { rawValue }

    var scale: CGFloat {
        switch self {
        case .small: 0.9
        case .medium: 1
        case .large: 1.15
        case .extraLarge: 1.3
        }
    }

    var displayLabel: String {
        switch self {
        case .small: String(localized: "preferences.interface.text_size.small")
        case .medium: String(localized: "preferences.interface.text_size.medium")
        case .large: String(localized: "preferences.interface.text_size.large")
        case .extraLarge: String(localized: "preferences.interface.text_size.extra_large")
        }
    }
}
