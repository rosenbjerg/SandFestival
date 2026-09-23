import Foundation
import Observation

@MainActor
@Observable
final class InterfacePreferences {
    var textSize: InterfaceTextSize {
        didSet {
            guard textSize != oldValue else { return }
            defaults.set(textSize.rawValue, forKey: Keys.textSize)
        }
    }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [Keys.textSize: InterfaceTextSize.medium.rawValue])
        let stored = defaults.string(forKey: Keys.textSize) ?? ""
        self.textSize = InterfaceTextSize(rawValue: stored) ?? .medium
    }

    private enum Keys {
        static let textSize = "interface.textSize"
    }
}
