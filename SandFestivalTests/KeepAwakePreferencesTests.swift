import Foundation
import Testing
@testable import SandFestival

@MainActor
@Suite("KeepAwakePreferences")
struct KeepAwakePreferencesTests {

    @Test("Defaults: enabled, only while plugged in")
    func freshInstanceMatchesRegisteredDefaults() {
        let prefs = KeepAwakePreferences(defaults: makeDefaults())
        #expect(prefs.isEnabled == true)
        #expect(prefs.onlyWhenPluggedIn == true)
    }

    @Test("Mutations persist to the same UserDefaults suite")
    func mutationsPersistAcrossInstances() {
        let defaults = makeDefaults()

        let first = KeepAwakePreferences(defaults: defaults)
        first.isEnabled = false
        first.onlyWhenPluggedIn = false

        let second = KeepAwakePreferences(defaults: defaults)
        #expect(second.isEnabled == false)
        #expect(second.onlyWhenPluggedIn == false)
    }

    @Test("didChange fires once per actual change, not on same-value writes")
    func didChangeFiresOnRealChangesOnly() {
        let prefs = KeepAwakePreferences(defaults: makeDefaults())
        var fired = 0
        prefs.didChange = { fired += 1 }

        prefs.isEnabled = true
        #expect(fired == 0)

        prefs.isEnabled = false
        prefs.onlyWhenPluggedIn = false
        #expect(fired == 2)
    }

    private func makeDefaults() -> UserDefaults {
        let name = "app.sandfestival.tests.keepawake.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}
