import Testing
@testable import SandFestival

@Suite("AttentionDecision")
struct AttentionDecisionTests {

    private let allEvents: Set<AttentionEvent> = Set(AttentionEvent.allCases)

    // MARK: - Bounce

    @Test("Bounces on an enabled event when app isn't frontmost and Focus is off")
    func bouncesOnEnabledEvent() {
        let d = AttentionDecision.decide(
            event: .permissionRequested,
            enabledEvents: allEvents,
            appIsFrontmost: false,
            isInFocusMode: false,
            notificationsEnabled: false,
            notificationTrigger: .unfocusedOnly
        )
        #expect(d.shouldBounce == true)
    }

    @Test("Does not bounce when app is frontmost")
    func suppressesBounceWhenFrontmost() {
        let d = AttentionDecision.decide(
            event: .permissionRequested,
            enabledEvents: allEvents,
            appIsFrontmost: true,
            isInFocusMode: false,
            notificationsEnabled: false,
            notificationTrigger: .unfocusedOnly
        )
        #expect(d.shouldBounce == false)
    }

    @Test("Does not bounce when system Focus is on")
    func suppressesBounceInFocusMode() {
        let d = AttentionDecision.decide(
            event: .permissionRequested,
            enabledEvents: allEvents,
            appIsFrontmost: false,
            isInFocusMode: true,
            notificationsEnabled: false,
            notificationTrigger: .unfocusedOnly
        )
        #expect(d.shouldBounce == false)
    }

    @Test("Does not bounce when the transition has no associated event")
    func suppressesBounceWithoutEvent() {
        let d = AttentionDecision.decide(
            event: nil,
            enabledEvents: allEvents,
            appIsFrontmost: false,
            isInFocusMode: false,
            notificationsEnabled: true,
            notificationTrigger: .always
        )
        #expect(d.shouldBounce == false)
        #expect(d.shouldNotify == false)
    }

    @Test("Does not bounce for an event the user disabled")
    func suppressesBounceForDisabledEvent() {
        let d = AttentionDecision.decide(
            event: .finishedOutputting,
            enabledEvents: [.permissionRequested],
            appIsFrontmost: false,
            isInFocusMode: false,
            notificationsEnabled: true,
            notificationTrigger: .always
        )
        #expect(d.shouldBounce == false)
        #expect(d.shouldNotify == false)
    }

    // MARK: - Notify

    @Test("Notifies on an enabled event when enabled, unfocused-only + not frontmost")
    func notifiesUnfocusedWhenUnfocused() {
        let d = AttentionDecision.decide(
            event: .permissionRequested,
            enabledEvents: allEvents,
            appIsFrontmost: false,
            isInFocusMode: false,
            notificationsEnabled: true,
            notificationTrigger: .unfocusedOnly
        )
        #expect(d.shouldNotify == true)
    }

    @Test("Suppresses unfocused-only notification when frontmost")
    func suppressesUnfocusedNotificationWhenFrontmost() {
        let d = AttentionDecision.decide(
            event: .permissionRequested,
            enabledEvents: allEvents,
            appIsFrontmost: true,
            isInFocusMode: false,
            notificationsEnabled: true,
            notificationTrigger: .unfocusedOnly
        )
        #expect(d.shouldNotify == false)
    }

    @Test("Notifies even when frontmost if trigger is .always")
    func notifiesAlwaysFiresWhenFrontmost() {
        let d = AttentionDecision.decide(
            event: .permissionRequested,
            enabledEvents: allEvents,
            appIsFrontmost: true,
            isInFocusMode: false,
            notificationsEnabled: true,
            notificationTrigger: .always
        )
        #expect(d.shouldNotify == true)
    }

    @Test("Does not notify when notifications are disabled")
    func suppressesNotificationWhenDisabled() {
        let d = AttentionDecision.decide(
            event: .permissionRequested,
            enabledEvents: allEvents,
            appIsFrontmost: false,
            isInFocusMode: false,
            notificationsEnabled: false,
            notificationTrigger: .always
        )
        #expect(d.shouldNotify == false)
    }

    @Test("Focus mode does not gate notifications — system handles that")
    func notificationsIgnoreFocusMode() {
        let d = AttentionDecision.decide(
            event: .permissionRequested,
            enabledEvents: allEvents,
            appIsFrontmost: false,
            isInFocusMode: true,
            notificationsEnabled: true,
            notificationTrigger: .unfocusedOnly
        )
        #expect(d.shouldNotify == true)
    }

    @Test("Bounces for finishedOutputting when it's in the enabled set")
    func bouncesForFinishedOutputting() {
        let d = AttentionDecision.decide(
            event: .finishedOutputting,
            enabledEvents: [.finishedOutputting],
            appIsFrontmost: false,
            isInFocusMode: false,
            notificationsEnabled: true,
            notificationTrigger: .unfocusedOnly
        )
        #expect(d.shouldBounce == true)
        #expect(d.shouldNotify == true)
    }
}
