import Foundation
import Observation

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

    var turnSummaries: ModelChoice {
        didSet {
            guard turnSummaries != oldValue else { return }
            defaults.set(turnSummaries.rawValue, forKey: Keys.turnSummaries)
        }
    }

    var enabledEvents: Set<AttentionEvent> {
        didSet {
            guard enabledEvents != oldValue else { return }
            defaults.set(enabledEvents.map(\.rawValue), forKey: Keys.enabledEvents)
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
            Keys.enabledEvents: AttentionPreferences.defaultEnabledEvents.map(\.rawValue),
            Keys.turnSummaries: ModelChoice.automatic.rawValue,
        ])
        self.dockBounceStyle =
            DockBounceStyle(rawValue: defaults.string(forKey: Keys.dockBounceStyle) ?? "")
            ?? .informational
        self.notificationsEnabled = defaults.bool(forKey: Keys.notificationsEnabled)
        self.notificationTrigger =
            NotificationTrigger(rawValue: defaults.string(forKey: Keys.notificationTrigger) ?? "")
            ?? .unfocusedOnly
        self.autoSurfaceActiveProject = defaults.bool(forKey: Keys.autoSurfaceActiveProject)
        self.turnSummaries = ModelChoice(rawValue: defaults.string(forKey: Keys.turnSummaries) ?? "") ?? .automatic
        let storedEvents = (defaults.array(forKey: Keys.enabledEvents) as? [String]) ?? []
        self.enabledEvents = Set(storedEvents.compactMap(AttentionEvent.init(rawValue:)))
    }

    static let defaultEnabledEvents: Set<AttentionEvent> = [
        .permissionRequested,
        .inputRequested,
        .blockedByAutoMode,
        .errored,
        .finishedOutputting,
    ]

    private enum Keys {
        static let dockBounceStyle = "attention.dockBounceStyle"
        static let notificationsEnabled = "attention.notificationsEnabled"
        static let notificationTrigger = "attention.notificationTrigger"
        static let autoSurfaceActiveProject = "attention.autoSurfaceActiveProject"
        static let enabledEvents = "attention.enabledEvents"
        static let turnSummaries = "attention.turnSummaries"
    }
}

extension ModelChoice {
    func makeSummarizer(
        agent: AgentTurnSummarization?,
        launcher: @escaping AgentLauncher
    ) -> (any TurnSummarizer)? {
        switch source(onDeviceAvailable: OnDeviceModel.isAvailable, agentModelAvailable: agent != nil) {
        case .onDevice: OnDeviceTurnSummarizer()
        case .agentModel: agent?.makeSummarizer(launcher)
        case nil: nil
        }
    }
}

enum DockBounceStyle: String, CaseIterable, Identifiable, Sendable {
    case informational
    case critical

    var id: String { rawValue }
}

enum NotificationTrigger: String, CaseIterable, Identifiable, Sendable {
    case unfocusedOnly
    case always

    var id: String { rawValue }
}
