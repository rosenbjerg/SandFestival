import Foundation
import Observation

/// User-facing knobs for how SandFestival pulls attention when a session
/// enters a `needsAttention` state. Backed by UserDefaults; defaults are
/// registered in `init` so a freshly-installed copy behaves predictably
/// without sprinkling `?? default` at every read site.
@MainActor
@Observable
final class AttentionPreferences {
    var dockBounceStyle: DockBounceStyle {
        didSet {
            guard dockBounceStyle != oldValue else { return }
            defaults.set(dockBounceStyle.rawValue, forKey: Keys.dockBounceStyle)
        }
    }

    var notificationsEnabled: Bool {
        didSet {
            guard notificationsEnabled != oldValue else { return }
            defaults.set(notificationsEnabled, forKey: Keys.notificationsEnabled)
        }
    }

    var notificationTrigger: NotificationTrigger {
        didSet {
            guard notificationTrigger != oldValue else { return }
            defaults.set(notificationTrigger.rawValue, forKey: Keys.notificationTrigger)
        }
    }

    var autoSurfaceActiveProject: Bool {
        didSet {
            guard autoSurfaceActiveProject != oldValue else { return }
            defaults.set(autoSurfaceActiveProject, forKey: Keys.autoSurfaceActiveProject)
        }
    }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Keys.dockBounceStyle: DockBounceStyle.informational.rawValue,
            Keys.notificationsEnabled: false,
            Keys.notificationTrigger: NotificationTrigger.unfocusedOnly.rawValue,
            Keys.autoSurfaceActiveProject: false,
        ])
        self.dockBounceStyle =
            DockBounceStyle(rawValue: defaults.string(forKey: Keys.dockBounceStyle) ?? "")
            ?? .informational
        self.notificationsEnabled = defaults.bool(forKey: Keys.notificationsEnabled)
        self.notificationTrigger =
            NotificationTrigger(rawValue: defaults.string(forKey: Keys.notificationTrigger) ?? "")
            ?? .unfocusedOnly
        self.autoSurfaceActiveProject = defaults.bool(forKey: Keys.autoSurfaceActiveProject)
    }

    private enum Keys {
        static let dockBounceStyle = "attention.dockBounceStyle"
        static let notificationsEnabled = "attention.notificationsEnabled"
        static let notificationTrigger = "attention.notificationTrigger"
        static let autoSurfaceActiveProject = "attention.autoSurfaceActiveProject"
    }
}

/// Mirrors `NSApplication.RequestUserAttentionType`. `.critical` keeps the
/// Dock icon bouncing until SandFestival is brought to the front;
/// `.informational` bounces once.
enum DockBounceStyle: String, CaseIterable, Identifiable, Sendable {
    case informational
    case critical

    var id: String { rawValue }
}

/// When the user has opted into delivering notifications, this controls
/// whether they fire only when SandFestival isn't focused, or always.
enum NotificationTrigger: String, CaseIterable, Identifiable, Sendable {
    case unfocusedOnly
    case always

    var id: String { rawValue }
}
