import Foundation
import Testing
@testable import SandFestival

@MainActor
@Suite("DictationPreferences")
struct DictationPreferencesTests {

    @Test("defaults to on-device clean-up")
    func defaultsToOnDevice() {
        #expect(DictationPreferences(defaults: makeDefaults()).cleanup == .onDevice)
    }

    @Test("persists the chosen clean-up")
    func persists() {
        let defaults = makeDefaults()
        DictationPreferences(defaults: defaults).cleanup = .claudeHaiku

        #expect(DictationPreferences(defaults: defaults).cleanup == .claudeHaiku)
    }

    @Test("an unknown stored value falls back to on-device")
    func unknownFallsBack() {
        let defaults = makeDefaults()
        defaults.set("gpt", forKey: "dictation.cleanup")

        #expect(DictationPreferences(defaults: defaults).cleanup == .onDevice)
    }

    private func makeDefaults() -> UserDefaults {
        let suite = "DictationPreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}
