import Testing
@testable import SandFestival

@Suite("AttentionDecision")
struct AttentionDecisionTests {

    // MARK: - Bounce

    @Test("Bounces on transition into attention when app isn't frontmost and Focus is off")
    func bouncesOnEnteringAttention() {
        let d = AttentionDecision.decide(
            wasAttention: false,
            isAttention: true,
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
            wasAttention: false,
            isAttention: true,
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
            wasAttention: false,
            isAttention: true,
            appIsFrontmost: false,
            isInFocusMode: true,
            notificationsEnabled: false,
            notificationTrigger: .unfocusedOnly
        )
        #expect(d.shouldBounce == false)
    }

    @Test("Does not bounce when already in attention (no transition)")
    func suppressesBounceOnSameStateAttention() {
        let d = AttentionDecision.decide(
            wasAttention: true,
            isAttention: true,
            appIsFrontmost: false,
            isInFocusMode: false,
            notificationsEnabled: false,
            notificationTrigger: .unfocusedOnly
        )
        #expect(d.shouldBounce == false)
    }

    @Test("Does not bounce on transition out of attention")
    func suppressesBounceOnTransitionOut() {
        let d = AttentionDecision.decide(
            wasAttention: true,
            isAttention: false,
            appIsFrontmost: false,
            isInFocusMode: false,
            notificationsEnabled: false,
            notificationTrigger: .unfocusedOnly
        )
        #expect(d.shouldBounce == false)
    }

    // MARK: - Notify

    @Test("Notifies on entering attention when enabled, unfocused-only + not frontmost")
    func notifiesUnfocusedWhenUnfocused() {
        let d = AttentionDecision.decide(
            wasAttention: false,
            isAttention: true,
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
            wasAttention: false,
            isAttention: true,
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
            wasAttention: false,
            isAttention: true,
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
            wasAttention: false,
            isAttention: true,
            appIsFrontmost: false,
            isInFocusMode: false,
            notificationsEnabled: false,
            notificationTrigger: .always
        )
        #expect(d.shouldNotify == false)
    }

    @Test("Does not notify on transition out of attention")
    func suppressesNotificationOnTransitionOut() {
        let d = AttentionDecision.decide(
            wasAttention: true,
            isAttention: false,
            appIsFrontmost: false,
            isInFocusMode: false,
            notificationsEnabled: true,
            notificationTrigger: .always
        )
        #expect(d.shouldNotify == false)
    }

    @Test("Focus mode does not gate notifications — system handles that")
    func notificationsIgnoreFocusMode() {
        let d = AttentionDecision.decide(
            wasAttention: false,
            isAttention: true,
            appIsFrontmost: false,
            isInFocusMode: true,
            notificationsEnabled: true,
            notificationTrigger: .unfocusedOnly
        )
        #expect(d.shouldNotify == true)
    }
}
