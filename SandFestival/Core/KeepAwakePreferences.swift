import Foundation
import Observation

/// User-facing knobs for holding the Mac out of idle sleep while agents
/// work. Backed by UserDefaults; defaults are registered in `init` so a
/// fresh install ships with the safe combination (on, but only while
/// plugged in) without `?? default` at every read site.
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

    /// Single subscriber — `KeepAwake` claims it so a toggle flipped in
    /// Settings re-evaluates the assertion immediately rather than on the
    /// next session transition.
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
