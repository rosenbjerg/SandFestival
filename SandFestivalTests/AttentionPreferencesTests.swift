import Foundation
import Testing
@testable import SandFestival

@MainActor
@Suite("AttentionPreferences")
struct AttentionPreferencesTests {

    @Test("Defaults: informational bounce, notifications off, unfocused-only trigger")
    func freshInstanceMatchesRegisteredDefaults() {
        let defaults = makeDefaults()
        let prefs = AttentionPreferences(defaults: defaults)
        #expect(prefs.dockBounceStyle == .informational)
        #expect(prefs.notificationsEnabled == false)
        #expect(prefs.notificationTrigger == .unfocusedOnly)
    }

    @Test("Mutations persist to the same UserDefaults suite")
    func mutationsPersistAcrossInstances() {
        let defaults = makeDefaults()

        let first = AttentionPreferences(defaults: defaults)
        first.dockBounceStyle = .critical
        first.notificationsEnabled = true
        first.notificationTrigger = .always

        let second = AttentionPreferences(defaults: defaults)
        #expect(second.dockBounceStyle == .critical)
        #expect(second.notificationsEnabled == true)
        #expect(second.notificationTrigger == .always)
    }

    @Test("Unrecognised stored raw values fall back to safe defaults")
    func unknownRawValuesFallBackToDefaults() {
        let defaults = makeDefaults()
        defaults.set("totally-bogus", forKey: "attention.dockBounceStyle")
        defaults.set("nope", forKey: "attention.notificationTrigger")

        let prefs = AttentionPreferences(defaults: defaults)
        #expect(prefs.dockBounceStyle == .informational)
        #expect(prefs.notificationTrigger == .unfocusedOnly)
    }

    // MARK: - Helpers

    private func makeDefaults() -> UserDefaults {
        let name = "app.sandfestival.tests.attention.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}
