import AppKit
import Foundation
import Intents
import UserNotifications

@MainActor
final class AttentionNotifier: NSObject {
    private let preferences: AttentionPreferences
    private weak var manager: SessionManager?
    private var pendingRequestID: Int?
    private var activationObserver: NSObjectProtocol?

    init(preferences: AttentionPreferences, manager: SessionManager) {
        self.preferences = preferences
        self.manager = manager
        super.init()

        manager.sessionStateObserver = { [weak self] session, old, new in
            self?.handleStateChange(session: session, from: old, to: new)
        }

        // macOS ends the bounce itself on activation; drop the id so a later
        // cancel can't hit a reused one.
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.pendingRequestID = nil }
        }

        UNUserNotificationCenter.current().delegate = self
        updateDockBadge()
    }

    deinit {
        if let activationObserver {
            NotificationCenter.default.removeObserver(activationObserver)
        }
    }

    // MARK: - Authorization

    func requestFocusAuthorization() {
        let center = INFocusStatusCenter.default
        guard center.authorizationStatus == .notDetermined else { return }
        center.requestAuthorization { _ in }
    }

    var focusAuthorizationStatus: INFocusStatusAuthorizationStatus {
        INFocusStatusCenter.default.authorizationStatus
    }

    @discardableResult
    func requestNotificationAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound])
            if !granted {
                preferences.notificationsEnabled = false
            }
            return granted
        } catch {
            preferences.notificationsEnabled = false
            return false
        }
    }

    func notificationAuthorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    // MARK: - Event handling

    private func handleStateChange(session: Session, from old: SessionState, to new: SessionState) {
        updateDockBadge()

        let event = AttentionEvent.from(transition: old, to: new)
        let decision = AttentionDecision.decide(
            event: event,
            enabledEvents: preferences.enabledEvents,
            appIsFrontmost: NSApp.isActive,
            isInFocusMode: isInFocusMode(),
            notificationsEnabled: preferences.notificationsEnabled,
            notificationTrigger: preferences.notificationTrigger
        )

        if decision.shouldBounce {
            issueBounce()
        }
        if decision.shouldNotify, let event {
            postNotification(for: session, event: event, state: new)
        }
        // Not `!new.needsAttention` alone: working → idle would withdraw the
        // finishedOutputting notification just posted.
        if old.needsAttention, !new.needsAttention {
            cancelBounceIfNoAttentionRemains()
            withdrawNotification(for: session.project.id)
        }
    }

    private func updateDockBadge() {
        let count = attentionCount()
        NSApp.dockTile.badgeLabel = count == 0 ? nil : "\(count)"
    }

    private func issueBounce() {
        if let prior = pendingRequestID {
            NSApp.cancelUserAttentionRequest(prior)
        }
        let type: NSApplication.RequestUserAttentionType =
            preferences.dockBounceStyle == .critical ? .criticalRequest : .informationalRequest
        pendingRequestID = NSApp.requestUserAttention(type)
    }

    private func cancelBounceIfNoAttentionRemains() {
        guard attentionCount() == 0, let id = pendingRequestID else { return }
        NSApp.cancelUserAttentionRequest(id)
        pendingRequestID = nil
    }

    private func attentionCount() -> Int {
        manager?.attentionSessions.count ?? 0
    }

    private func isInFocusMode() -> Bool {
        let center = INFocusStatusCenter.default
        guard center.authorizationStatus == .authorized else { return false }
        return center.focusStatus.isFocused ?? false
    }

    // MARK: - Notifications

    private func postNotification(for session: Session, event: AttentionEvent, state: SessionState) {
        let content = UNMutableNotificationContent()
        content.title = session.project.name
        content.body = Self.notificationBody(for: event, state: state)
        content.sound = .default
        content.userInfo = [Self.projectIDKey: session.project.id.uuidString]
        let request = UNNotificationRequest(
            identifier: Self.notificationIdentifier(for: session.project.id),
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { _ in }
    }

    private func withdrawNotification(for projectID: Project.ID) {
        let center = UNUserNotificationCenter.current()
        let id = Self.notificationIdentifier(for: projectID)
        center.removeDeliveredNotifications(withIdentifiers: [id])
        center.removePendingNotificationRequests(withIdentifiers: [id])
    }

    private static func notificationIdentifier(for projectID: Project.ID) -> String {
        "sandfestival.attention.\(projectID.uuidString)"
    }

    nonisolated static let projectIDKey = "projectID"

    private static func notificationBody(for event: AttentionEvent, state: SessionState) -> String {
        switch event {
        case .permissionRequested:
            return String(localized: "notification.body.waiting_permission")
        case .inputRequested:
            return String(localized: "notification.body.waiting_idle")
        case .blockedByAutoMode:
            return String(localized: "notification.body.blocked_auto_mode")
        case .errored:
            if case .errored(let reason) = state {
                return String(format: String(localized: "notification.body.errored"), reason)
            }
            return String(localized: "notification.body.generic")
        case .finishedOutputting:
            return String(localized: "notification.body.finished_outputting")
        }
    }

    private func focusProject(id: UUID) {
        manager?.focus(projectID: id)
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension AttentionNotifier: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping @Sendable (UNNotificationPresentationOptions) -> Void
    ) {
        // Without this the .always trigger shows nothing while SandFestival is frontmost.
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping @Sendable () -> Void
    ) {
        let info = response.notification.request.content.userInfo
        let projectID: UUID? = {
            guard let raw = info[Self.projectIDKey] as? String else { return nil }
            return UUID(uuidString: raw)
        }()
        Task { @MainActor [weak self] in
            if let projectID {
                self?.focusProject(id: projectID)
            }
            completionHandler()
        }
    }
}

struct AttentionDecision: Equatable, Sendable {
    var shouldBounce: Bool
    var shouldNotify: Bool

    static func decide(
        event: AttentionEvent?,
        enabledEvents: Set<AttentionEvent>,
        appIsFrontmost: Bool,
        isInFocusMode: Bool,
        notificationsEnabled: Bool,
        notificationTrigger: NotificationTrigger
    ) -> AttentionDecision {
        guard let event, enabledEvents.contains(event) else {
            return AttentionDecision(shouldBounce: false, shouldNotify: false)
        }
        let shouldBounce = !appIsFrontmost && !isInFocusMode
        let shouldNotify =
            notificationsEnabled
            && (notificationTrigger == .always || !appIsFrontmost)
        return AttentionDecision(shouldBounce: shouldBounce, shouldNotify: shouldNotify)
    }
}
