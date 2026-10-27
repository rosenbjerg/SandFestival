import Foundation
import Observation

enum TranscriptCleanup: String, CaseIterable, Identifiable {
    case off
    case onDevice
    case claudeHaiku

    var id: String { rawValue }

    var displayLabel: String {
        switch self {
        case .off: String(localized: "preferences.dictation.cleanup.off")
        case .onDevice: String(localized: "preferences.dictation.cleanup.on_device")
        case .claudeHaiku: String(localized: "preferences.dictation.cleanup.claude_haiku")
        }
    }
}

@MainActor
@Observable
final class DictationPreferences {
    var cleanup: TranscriptCleanup {
        didSet {
            guard cleanup != oldValue else { return }
            defaults.set(cleanup.rawValue, forKey: Keys.cleanup)
        }
    }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [Keys.cleanup: TranscriptCleanup.onDevice.rawValue])
        let stored = defaults.string(forKey: Keys.cleanup) ?? ""
        self.cleanup = TranscriptCleanup(rawValue: stored) ?? .onDevice
    }

    private enum Keys {
        static let cleanup = "dictation.cleanup"
    }
}
