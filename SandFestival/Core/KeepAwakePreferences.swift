import Foundation
import Observation

@MainActor
@Observable
final class KeepAwakePreferences {
    var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            defaults.set(isEnabled, forKey: Keys.isEnabled)
            didChange?()
        }
    }

    var onlyWhenPluggedIn: Bool {
        didSet {
            guard onlyWhenPluggedIn != oldValue else { return }
            defaults.set(onlyWhenPluggedIn, forKey: Keys.onlyWhenPluggedIn)
            didChange?()
        }
    }

    @ObservationIgnored var didChange: (() -> Void)?

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Keys.isEnabled: true,
            Keys.onlyWhenPluggedIn: true,
        ])
        self.isEnabled = defaults.bool(forKey: Keys.isEnabled)
        self.onlyWhenPluggedIn = defaults.bool(forKey: Keys.onlyWhenPluggedIn)
    }

    private enum Keys {
        static let isEnabled = "keepAwake.enabled"
        static let onlyWhenPluggedIn = "keepAwake.onlyWhenPluggedIn"
    }
}
