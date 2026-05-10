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

    @Test("working + .heartbeat stays working")
    func workingHeartbeatStaysWorking() {
        #expect(SessionStateMachine.next(from: .working, event: .heartbeat) == .working)
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

    // MARK: - No-op edges

    @Test("idle + .heartbeat is a no-op")
    func idleHeartbeatIsNoOp() {
        #expect(SessionStateMachine.next(from: .idle, event: .heartbeat) == .idle)
    }

    @Test("starting + unrelated events stay in starting")
    func startingIgnoresUnrelatedEvents() {
        let unrelated: [AgentEvent] = [.heartbeat, .idle, .waitingForPermission, .blockedByAutoMode]
        for event in unrelated {
            #expect(SessionStateMachine.next(from: .starting, event: event) == .starting)
        }
    }

    @Test("attention states ignore .heartbeat")
    func attentionStatesIgnoreHeartbeat() {
        let attentionStates: [SessionState] = [.waitingForPermission, .waitingForIdle, .blockedByAutoMode]
        for state in attentionStates {
            #expect(SessionStateMachine.next(from: state, event: .heartbeat) == state)
        }
    }
}
