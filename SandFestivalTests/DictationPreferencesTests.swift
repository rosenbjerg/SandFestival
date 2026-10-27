import Foundation
import Testing
@testable import SandFestival

@MainActor
@Suite("DictationPreferences")
struct DictationPreferencesTests {

    @Test("defaults to automatic clean-up")
    func defaultsToAutomatic() {
        #expect(DictationPreferences(defaults: makeDefaults()).cleanup == .automatic)
    }

    @Test("persists the chosen clean-up")
    func persists() {
        let defaults = makeDefaults()
        DictationPreferences(defaults: defaults).cleanup = .agentModel

        #expect(DictationPreferences(defaults: defaults).cleanup == .agentModel)
    }

    @Test("an unknown stored value falls back to automatic")
    func unknownFallsBack() {
        let defaults = makeDefaults()
        defaults.set("gpt", forKey: "dictation.cleanup")

        #expect(DictationPreferences(defaults: defaults).cleanup == .automatic)
    }

    @Test("the silence timeout defaults to 2.5 s and persists")
    func silenceTimeoutPersists() {
        let defaults = makeDefaults()
        #expect(DictationPreferences(defaults: defaults).silenceTimeout == 2.5)

        DictationPreferences(defaults: defaults).silenceTimeout = 4

        let reloaded = DictationPreferences(defaults: defaults)
        #expect(reloaded.silenceTimeout == 4)
        #expect(reloaded.endpointConfiguration.silenceTimeout == 4)
    }

    @Test("a stored silence timeout outside the range is clamped")
    func silenceTimeoutClamped() {
        let defaults = makeDefaults()
        defaults.set(0.2, forKey: "dictation.silenceTimeout")
        #expect(DictationPreferences(defaults: defaults).silenceTimeout == 1.5)

        defaults.set(30.0, forKey: "dictation.silenceTimeout")
        #expect(DictationPreferences(defaults: defaults).silenceTimeout == 5)
    }

    @Test("sending after paste is off by default and persists")
    func submitsAfterPastePersists() {
        let defaults = makeDefaults()
        #expect(DictationPreferences(defaults: defaults).submitsAfterPaste == false)

        DictationPreferences(defaults: defaults).submitsAfterPaste = true

        #expect(DictationPreferences(defaults: defaults).submitsAfterPaste == true)
    }

    private func makeDefaults() -> UserDefaults {
        let suite = "DictationPreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}
