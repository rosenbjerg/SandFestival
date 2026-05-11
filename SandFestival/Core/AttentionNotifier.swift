import AppKit
import Foundation
import Intents

/// Bridges session state changes to macOS attention surfaces: dock badge
/// (always reflects current count), dock bounce (only on transitions into
/// `needsAttention`, only when SandFestival isn't frontmost, and only when
/// system Focus is off), and — in a follow-on commit — user notifications.
///
/// macOS doesn't ship a public API for "is system Focus on" outside of
/// Intents framework's `INFocusStatusCenter`, which is gated on user
/// authorization. When authorization hasn't been granted we fall through
/// (treat Focus as off) — bouncing in that mode is the conservative choice
/// because the user can mute it via `dockBounceStyle` or by disabling
/// notifications wholesale.
@MainActor
final class AttentionNotifier {
    private let preferences: AttentionPreferences
    private weak var manager: SessionManager?
    private var pendingRequestID: Int?
    private var activationObserver: NSObjectProtocol?

    init(preferences: AttentionPreferences, manager: SessionManager) {
        self.preferences = preferences
        self.manager = manager

        manager.sessionStateObserver = { [weak self] _, old, new in
            self?.handleStateChange(from: old, to: new)
        }

        // When the user brings the app to the front, macOS stops any pending
        // attention bounce on its own — but we need to drop our tracking id
        // so we don't try to cancel a stale request later.
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.pendingRequestID = nil }
        }

        updateDockBadge()
    }

    deinit {
        if let activationObserver {
            NotificationCenter.default.removeObserver(activationObserver)
        }
    }

    // MARK: - Authorization

    /// Triggers the system Focus-status prompt if it hasn't been answered
    /// yet. No-op when the user has already accepted or denied.
    func requestFocusAuthorization() {
        let center = INFocusStatusCenter.default
        guard center.authorizationStatus == .notDetermined else { return }
        center.requestAuthorization { _ in }
    }

    var focusAuthorizationStatus: INFocusStatusAuthorizationStatus {
        INFocusStatusCenter.default.authorizationStatus
    }

    // MARK: - Event handling

    private func handleStateChange(from old: SessionState, to new: SessionState) {
        updateDockBadge()

        let decision = AttentionDecision.decide(
            wasAttention: old.needsAttention,
            isAttention: new.needsAttention,
            appIsFrontmost: NSApp.isActive,
            isInFocusMode: isInFocusMode(),
            notificationsEnabled: preferences.notificationsEnabled,
            notificationTrigger: preferences.notificationTrigger
        )

        if decision.shouldBounce {
            issueBounce()
        }
        if !new.needsAttention {
            cancelBounceIfNoAttentionRemains()
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
        guard let manager else { return 0 }
        return manager.projects
            .compactMap { manager.session(for: $0.id) }
            .filter(\.state.needsAttention)
            .count
    }

    private func isInFocusMode() -> Bool {
        let center = INFocusStatusCenter.default
        guard center.authorizationStatus == .authorized else { return false }
        return center.focusStatus.isFocused ?? false
    }
}

/// Pure decision logic split out so it's testable without spinning up
/// AppKit or a real Focus center. The notifier owns side effects;
/// `decide` only answers "given the world right now, what should fire?"
struct AttentionDecision: Equatable, Sendable {
    var shouldBounce: Bool
    var shouldNotify: Bool

    static func decide(
        wasAttention: Bool,
        isAttention: Bool,
        appIsFrontmost: Bool,
        isInFocusMode: Bool,
        notificationsEnabled: Bool,
        notificationTrigger: NotificationTrigger
    ) -> AttentionDecision {
        let transitionIn = isAttention && !wasAttention
        let shouldBounce = transitionIn && !appIsFrontmost && !isInFocusMode
        let shouldNotify =
            transitionIn
            && notificationsEnabled
            && (notificationTrigger == .always || !appIsFrontmost)
        return AttentionDecision(shouldBounce: shouldBounce, shouldNotify: shouldNotify)
    }
}
