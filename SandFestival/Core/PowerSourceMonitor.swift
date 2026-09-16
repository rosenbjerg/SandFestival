import Foundation
import IOKit.ps

/// Whether the Mac is drawing from mains power, plus a change signal.
/// Abstracted so `KeepAwake` can be tested by flipping a stub instead of
/// pulling a laptop's charger.
@MainActor
protocol PowerSourceMonitor: AnyObject {
    var isPluggedIn: Bool { get }
    var onChange: (() -> Void)? { get set }
}

/// Backed by `IOPSCreateLimitedPowerNotification`, which posts only on
/// AC↔battery/UPS transitions — unlike `IOPSNotificationCreateRunLoopSource`,
/// which also fires on every percent-remaining tick. The callback carries no
/// payload, so `isPluggedIn` re-reads the providing source each time.
@MainActor
final class IOKitPowerSourceMonitor: PowerSourceMonitor {
    var onChange: (() -> Void)?

    private var source: CFRunLoopSource?

    init() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        source = IOPSCreateLimitedPowerNotification(powerSourceDidChange, context)?.takeRetainedValue()
        if let source {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        }
    }

    deinit {
        if let source {
            CFRunLoopSourceInvalidate(source)
        }
    }

    var isPluggedIn: Bool {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(snapshot)?.takeUnretainedValue()
        else { return true }
        return (type as String) == kIOPMACPowerKey
    }

    fileprivate func handleChange() {
        onChange?()
    }
}

// The source is scheduled on the main run loop, so the callback lands on the
// main thread; `assumeIsolated` is what lets a C function pointer reach a
// MainActor object.
private nonisolated func powerSourceDidChange(_ context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    let monitor = Unmanaged<IOKitPowerSourceMonitor>.fromOpaque(context).takeUnretainedValue()
    MainActor.assumeIsolated {
        monitor.handleChange()
    }
}
