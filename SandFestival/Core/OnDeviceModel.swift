import Foundation
import FoundationModels

nonisolated enum OnDeviceModel {
    static var isAvailable: Bool {
        SystemLanguageModel.default.isAvailable
    }

    static var unavailableReason: String? {
        switch SystemLanguageModel.default.availability {
        case .available:
            nil
        case .unavailable(.deviceNotEligible):
            String(localized: "preferences.on_device.unavailable.device")
        case .unavailable(.appleIntelligenceNotEnabled):
            String(localized: "preferences.on_device.unavailable.disabled")
        case .unavailable(.modelNotReady):
            String(localized: "preferences.on_device.unavailable.not_ready")
        case .unavailable:
            String(localized: "preferences.on_device.unavailable.other")
        }
    }
}
