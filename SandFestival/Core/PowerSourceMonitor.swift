import Foundation
import IOKit.ps

@MainActor
protocol PowerSourceMonitor: AnyObject {
    var isPluggedIn: Bool { get }
    var onChange: (() -> Void)? { get set }
}

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

private nonisolated func powerSourceDidChange(_ context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    let monitor = Unmanaged<IOKitPowerSourceMonitor>.fromOpaque(context).takeUnretainedValue()
    MainActor.assumeIsolated {
        monitor.handleChange()
    }
}
