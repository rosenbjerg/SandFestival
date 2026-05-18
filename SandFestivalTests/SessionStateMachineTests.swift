import Testing
@testable import SandFestival

@Suite("SessionStateMachine")
struct SessionStateMachineTests {

    // MARK: - Spec'd transitions

    @Test("starting + .started → idle")
    func startingPlusStartedGoesIdle() {
        #expect(SessionStateMachine.next(from: .starting, event: .started) == .idle)
    }

    @Test("idle + .working → working")
    func idlePlusWorkingGoesWorking() {
        #expect(SessionStateMachine.next(from: .idle, event: .working) == .working)
    }

    @Test("working + .idle → idle")
    func workingPlusIdleGoesIdle() {
        #expect(SessionStateMachine.next(from: .working, event: .idle) == .idle)
    }

    @Test("working + .waitingForPermission → waitingForPermission")
    func workingPlusWaitingForPermission() {
        #expect(SessionStateMachine.next(from: .working, event: .waitingForPermission) == .waitingForPermission)
    }

    @Test("working + .waitingForInput → waitingForIdle (per spec naming)")
    func workingPlusWaitingForInputMapsToWaitingIdle() {
        #expect(SessionStateMachine.next(from: .working, event: .waitingForInput) == .waitingForIdle)
    }

    @Test("working + .blockedByAutoMode → blockedByAutoMode")
    func workingPlusBlockedByAutoMode() {
        #expect(SessionStateMachine.next(from: .working, event: .blockedByAutoMode) == .blockedByAutoMode)
    }

    @Test("working + .errored carries the reason through")
    func workingPlusErroredCarriesReason() {
        let next = SessionStateMachine.next(from: .working, event: .errored(reason: "boom"))
        #expect(next == .errored(reason: "boom"))
    }

    @Test("attention states + .working → working")
    func attentionStatesGoBackToWorking() {
        let attentionStates: [SessionState] = [.waitingForPermission, .waitingForIdle, .blockedByAutoMode]
        for state in attentionStates {
            #expect(SessionStateMachine.next(from: state, event: .working) == .working)
        }
    }

    @Test("any state + .stopped → stopped")
    func anyStateGoesStoppedOnStopped() {
        let allStates: [SessionState] = [
            .starting, .idle, .working,
            .waitingForPermission, .waitingForIdle, .blockedByAutoMode,
            .errored(reason: "x"), .stopped,
        ]
        for state in allStates {
            #expect(SessionStateMachine.next(from: state, event: .stopped) == .stopped)
        }
    }

    // MARK: - Recovery / restart paths

    @Test("stopped + .started → idle (session respawn)")
    func stoppedPlusStartedGoesIdle() {
        #expect(SessionStateMachine.next(from: .stopped, event: .started) == .idle)
    }

    @Test("errored + .working → working (recovery)")
    func erroredPlusWorkingRecovers() {
        #expect(SessionStateMachine.next(from: .errored(reason: "x"), event: .working) == .working)
    }

    @Test("errored + .started → idle (post-restart)")
    func erroredPlusStartedGoesIdle() {
        #expect(SessionStateMachine.next(from: .errored(reason: "x"), event: .started) == .idle)
    }

    @Test(".sessionRestarted drives the same transitions as .started")
    func sessionRestartedMirrorsStarted() {
        // `.sessionRestarted` is `/resume` / `/clear` — the side effect lives
        // in Session.apply (drop the stale terminal title); state-machine
        // transitions are identical to `.started`.
        #expect(SessionStateMachine.next(from: .starting, event: .sessionRestarted) == .idle)
        #expect(SessionStateMachine.next(from: .errored(reason: "x"), event: .sessionRestarted) == .idle)
        #expect(SessionStateMachine.next(from: .stopped, event: .sessionRestarted) == .idle)
        // On a live session it's a no-op, same as `.started`.
        for state in [SessionState.idle, .working, .waitingForPermission, .waitingForIdle, .blockedByAutoMode] {
            #expect(SessionStateMachine.next(from: state, event: .sessionRestarted) == state)
        }
    }

    // MARK: - No-op edges

    @Test("starting + unrelated events stay in starting")
    func startingIgnoresUnrelatedEvents() {
        let unrelated: [AgentEvent] = [.idle, .waitingForPermission, .blockedByAutoMode]
        for event in unrelated {
            #expect(SessionStateMachine.next(from: .starting, event: event) == .starting)
        }
    }

    // MARK: - User interaction

    @Test("waitingForIdle + .userInteracted → idle")
    func waitingForIdleResolvesOnUserInteraction() {
        // Claude Code emits no hook when the user dismisses AskUserQuestion
        // with Ctrl+C, so terminal input is the fallback resolution signal.
        #expect(SessionStateMachine.next(from: .waitingForIdle, event: .userInteracted) == .idle)
    }

    @Test(".userInteracted is ignored in every other state")
    func userInteractedIgnoredOutsideWaitingForIdle() {
        // Typing during e.g. waitingForPermission must not fake a grant —
        // those states have their own resolution paths.
        let ignoringStates: [SessionState] = [
            .starting, .idle, .working,
            .waitingForPermission, .blockedByAutoMode,
            .errored(reason: "x"), .stopped,
        ]
        for state in ignoringStates {
            #expect(SessionStateMachine.next(from: state, event: .userInteracted) == state)
        }
    }
}
