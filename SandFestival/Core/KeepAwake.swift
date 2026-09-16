import Foundation

/// Something that can hold the system out of idle sleep. Abstracted so
/// `KeepAwake` tests can count holds and releases instead of touching
/// power management.
@MainActor
protocol SleepAssertion: AnyObject {
    func hold(reason: String)
    func release()
}

/// The production assertion: `ProcessInfo.beginActivity` with
/// `.idleSystemSleepDisabled`, which is what `caffeinate -i` takes out.
/// Display sleep and lid-close sleep are untouched. powerd attributes the
/// assertion to this process and drops it if the process dies, which is
/// why this is an in-process call rather than a spawned `caffeinate`.
@MainActor
final class IdleSleepAssertion: SleepAssertion {
    private var token: (any NSObjectProtocol)?

    func hold(reason: String) {
        guard token == nil else { return }
        token = ProcessInfo.processInfo.beginActivity(options: .idleSystemSleepDisabled, reason: reason)
    }

    func release() {
        guard let token else { return }
        ProcessInfo.processInfo.endActivity(token)
        self.token = nil
    }
}

/// Holds an idle-sleep assertion while any session is `.working`, gated on
/// `KeepAwakePreferences` and the power source. Same split as
/// `AttentionDecision`: `shouldHold` is pure, the instance owns the side
/// effect and reconciles whenever any input changes.
@MainActor
final class KeepAwake {
    private(set) var isHolding = false

    var anyWorking = false {
        didSet { reconcile() }
    }

    private let preferences: KeepAwakePreferences
    private let assertion: any SleepAssertion
    private let powerSource: any PowerSourceMonitor

    init(
        preferences: KeepAwakePreferences,
        assertion: (any SleepAssertion)? = nil,
        powerSource: (any PowerSourceMonitor)? = nil
    ) {
        self.preferences = preferences
        self.assertion = assertion ?? IdleSleepAssertion()
        self.powerSource = powerSource ?? IOKitPowerSourceMonitor()
        preferences.didChange = { [weak self] in self?.reconcile() }
        self.powerSource.onChange = { [weak self] in self?.reconcile() }
    }

    static func shouldHold(anyWorking: Bool, enabled: Bool, onlyWhenPluggedIn: Bool, isPluggedIn: Bool) -> Bool {
        anyWorking && enabled && (isPluggedIn || !onlyWhenPluggedIn)
    }

    private func reconcile() {
        let wanted = KeepAwake.shouldHold(
            anyWorking: anyWorking,
            enabled: preferences.isEnabled,
            onlyWhenPluggedIn: preferences.onlyWhenPluggedIn,
            isPluggedIn: powerSource.isPluggedIn
        )
        guard wanted != isHolding else { return }
        if wanted {
            assertion.hold(reason: "An agent session is working")
        } else {
            assertion.release()
        }
        isHolding = wanted
    }
}
