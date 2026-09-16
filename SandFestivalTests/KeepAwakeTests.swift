import Foundation
import Testing
@testable import SandFestival

@MainActor
@Suite("KeepAwake")
struct KeepAwakeTests {

    @Test("holds while working, plugged in, and enabled")
    func holdsInTheHappyPath() {
        let (keepAwake, assertion, _) = makeKeepAwake()

        keepAwake.anyWorking = true

        #expect(keepAwake.isHolding)
        #expect(assertion.holds == 1)
        #expect(assertion.releases == 0)
    }

    @Test("releases when the last session stops working")
    func releasesWhenIdle() {
        let (keepAwake, assertion, _) = makeKeepAwake()
        keepAwake.anyWorking = true

        keepAwake.anyWorking = false

        #expect(!keepAwake.isHolding)
        #expect(assertion.releases == 1)
    }

    @Test("disabled preference never holds")
    func disabledNeverHolds() {
        let (keepAwake, assertion, _) = makeKeepAwake(enabled: false)

        keepAwake.anyWorking = true

        #expect(!keepAwake.isHolding)
        #expect(assertion.holds == 0)
    }

    @Test("on battery with plugged-in-only, working does not hold")
    func batteryBlocksHold() {
        let (keepAwake, assertion, _) = makeKeepAwake(pluggedIn: false)

        keepAwake.anyWorking = true

        #expect(!keepAwake.isHolding)
        #expect(assertion.holds == 0)
    }

    @Test("on battery with battery allowed, working holds")
    func batteryAllowedHolds() {
        let (keepAwake, assertion, _) = makeKeepAwake(onlyWhenPluggedIn: false, pluggedIn: false)

        keepAwake.anyWorking = true

        #expect(keepAwake.isHolding)
        #expect(assertion.holds == 1)
    }

    @Test("unplugging mid-work releases; plugging back in re-holds")
    func reactsToPowerSourceChanges() {
        let (keepAwake, assertion, power) = makeKeepAwake()
        keepAwake.anyWorking = true
        #expect(keepAwake.isHolding)

        power.isPluggedIn = false
        power.onChange?()
        #expect(!keepAwake.isHolding)
        #expect(assertion.releases == 1)

        power.isPluggedIn = true
        power.onChange?()
        #expect(keepAwake.isHolding)
        #expect(assertion.holds == 2)
    }

    @Test("turning the preference off mid-work releases; on again re-holds")
    func reactsToPreferenceChanges() {
        let prefs = makePreferences()
        let (keepAwake, assertion, _) = makeKeepAwake(preferences: prefs)
        keepAwake.anyWorking = true

        prefs.isEnabled = false
        #expect(!keepAwake.isHolding)
        #expect(assertion.releases == 1)

        prefs.isEnabled = true
        #expect(keepAwake.isHolding)
        #expect(assertion.holds == 2)
    }

    @Test("allowing battery while unplugged and working takes the hold immediately")
    func allowingBatteryTakesHold() {
        let prefs = makePreferences()
        let (keepAwake, assertion, _) = makeKeepAwake(preferences: prefs, pluggedIn: false)
        keepAwake.anyWorking = true
        #expect(!keepAwake.isHolding)

        prefs.onlyWhenPluggedIn = false

        #expect(keepAwake.isHolding)
        #expect(assertion.holds == 1)
    }

    @Test("power changes while nothing is working are no-ops")
    func powerChangeWhileIdleIsNoop() {
        let (keepAwake, assertion, power) = makeKeepAwake()

        power.isPluggedIn = false
        power.onChange?()
        power.isPluggedIn = true
        power.onChange?()

        #expect(!keepAwake.isHolding)
        #expect(assertion.holds == 0)
        #expect(assertion.releases == 0)
    }

    @Test("repeated identical inputs never double-hold or double-release")
    func idempotent() {
        let (keepAwake, assertion, power) = makeKeepAwake()

        keepAwake.anyWorking = true
        keepAwake.anyWorking = true
        power.onChange?()
        #expect(assertion.holds == 1)

        keepAwake.anyWorking = false
        keepAwake.anyWorking = false
        power.onChange?()
        #expect(assertion.releases == 1)
    }

    // MARK: - Helpers

    private func makeKeepAwake(
        preferences: KeepAwakePreferences? = nil,
        enabled: Bool = true,
        onlyWhenPluggedIn: Bool = true,
        pluggedIn: Bool = true
    ) -> (KeepAwake, RecordingSleepAssertion, StubPowerSourceMonitor) {
        let prefs = preferences ?? makePreferences()
        prefs.isEnabled = enabled
        prefs.onlyWhenPluggedIn = onlyWhenPluggedIn
        let assertion = RecordingSleepAssertion()
        let power = StubPowerSourceMonitor(isPluggedIn: pluggedIn)
        let keepAwake = KeepAwake(preferences: prefs, assertion: assertion, powerSource: power)
        return (keepAwake, assertion, power)
    }

    private func makePreferences() -> KeepAwakePreferences {
        let name = "app.sandfestival.tests.keepawake.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return KeepAwakePreferences(defaults: defaults)
    }
}

@MainActor
final class RecordingSleepAssertion: SleepAssertion {
    var holds = 0
    var releases = 0

    func hold(reason: String) { holds += 1 }
    func release() { releases += 1 }
}

@MainActor
final class StubPowerSourceMonitor: PowerSourceMonitor {
    var isPluggedIn: Bool
    var onChange: (() -> Void)?

    init(isPluggedIn: Bool) {
        self.isPluggedIn = isPluggedIn
    }
}
