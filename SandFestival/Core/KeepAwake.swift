import Foundation

@MainActor
protocol SleepAssertion: AnyObject {
    func hold(reason: String)
    func release()
}

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
