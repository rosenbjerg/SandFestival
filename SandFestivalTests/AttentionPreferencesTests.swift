import Foundation
import Testing
@testable import SandFestival

@MainActor
@Suite("AttentionPreferences")
struct AttentionPreferencesTests {

    @Test("Defaults: informational bounce, notifications off, unfocused-only trigger, auto-surface off")
    func freshInstanceMatchesRegisteredDefaults() {
        let defaults = makeDefaults()
        let prefs = AttentionPreferences(defaults: defaults)
        #expect(prefs.dockBounceStyle == .informational)
        #expect(prefs.notificationsEnabled == false)
        #expect(prefs.notificationTrigger == .unfocusedOnly)
        #expect(prefs.autoSurfaceActiveProject == false)
        #expect(prefs.enabledEvents == AttentionPreferences.defaultEnabledEvents)
    }

    @Test("Default enabled-events covers every attention state and finishedOutputting; stopped opt-in")
    func defaultEnabledEventsContents() {
        #expect(AttentionPreferences.defaultEnabledEvents.contains(.permissionRequested))
        #expect(AttentionPreferences.defaultEnabledEvents.contains(.inputRequested))
        #expect(AttentionPreferences.defaultEnabledEvents.contains(.blockedByAutoMode))
        #expect(AttentionPreferences.defaultEnabledEvents.contains(.errored))
        #expect(AttentionPreferences.defaultEnabledEvents.contains(.finishedOutputting))
        #expect(AttentionPreferences.defaultEnabledEvents.contains(.stopped) == false)
    }

    @Test("Mutations persist to the same UserDefaults suite")
    func mutationsPersistAcrossInstances() {
        let defaults = makeDefaults()

        let first = AttentionPreferences(defaults: defaults)
        first.dockBounceStyle = .critical
        first.notificationsEnabled = true
        first.notificationTrigger = .always
        first.autoSurfaceActiveProject = true
        first.enabledEvents = [.permissionRequested, .stopped]

        let second = AttentionPreferences(defaults: defaults)
        #expect(second.dockBounceStyle == .critical)
        #expect(second.notificationsEnabled == true)
        #expect(second.notificationTrigger == .always)
        #expect(second.autoSurfaceActiveProject == true)
        #expect(second.enabledEvents == [.permissionRequested, .stopped])
    }

    @Test("Enabled-events insertion through the property fires didSet")
    func enabledEventsMutationPersists() {
        let defaults = makeDefaults()
        let prefs = AttentionPreferences(defaults: defaults)
        prefs.enabledEvents = []
        prefs.enabledEvents.insert(.finishedOutputting)

        let reloaded = AttentionPreferences(defaults: defaults)
        #expect(reloaded.enabledEvents == [.finishedOutputting])
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

    @Test("Stored event rawValues that no longer exist are dropped without poisoning the set")
    func unknownEventRawValuesAreDropped() {
        let defaults = makeDefaults()
        defaults.set(["permissionRequested", "from_a_future_version"], forKey: "attention.enabledEvents")

        let prefs = AttentionPreferences(defaults: defaults)
        #expect(prefs.enabledEvents == [.permissionRequested])
    }

    // MARK: - Helpers

    private func makeDefaults() -> UserDefaults {
        let name = "app.sandfestival.tests.attention.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}
