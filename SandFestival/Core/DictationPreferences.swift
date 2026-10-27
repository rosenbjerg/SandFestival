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

    var silenceTimeout: TimeInterval {
        didSet {
            guard silenceTimeout != oldValue else { return }
            defaults.set(silenceTimeout, forKey: Keys.silenceTimeout)
        }
    }

    var endpointConfiguration: DictationEndpointer.Configuration {
        DictationEndpointer.Configuration(silenceTimeout: silenceTimeout)
    }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Keys.cleanup: TranscriptCleanup.onDevice.rawValue,
            Keys.silenceTimeout: DictationEndpointer.Configuration.defaultSilenceTimeout,
        ])
        let stored = defaults.string(forKey: Keys.cleanup) ?? ""
        self.cleanup = TranscriptCleanup(rawValue: stored) ?? .onDevice
        let range = DictationEndpointer.Configuration.silenceTimeoutRange
        self.silenceTimeout = min(max(defaults.double(forKey: Keys.silenceTimeout), range.lowerBound), range.upperBound)
    }

    private enum Keys {
        static let cleanup = "dictation.cleanup"
        static let silenceTimeout = "dictation.silenceTimeout"
    }
}
