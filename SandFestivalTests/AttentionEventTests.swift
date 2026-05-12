import Testing
@testable import SandFestival

@Suite("AttentionEvent.from(transition:to:)")
struct AttentionEventTests {

    @Test("Entering waitingForPermission maps to permissionRequested")
    func permission() {
        #expect(
            AttentionEvent.from(transition: .working, to: .waitingForPermission)
                == .permissionRequested
        )
    }

    @Test("Entering waitingForIdle maps to inputRequested")
    func input() {
        #expect(
            AttentionEvent.from(transition: .working, to: .waitingForIdle)
                == .inputRequested
        )
    }

    @Test("Entering blockedByAutoMode maps to blockedByAutoMode")
    func blocked() {
        #expect(
            AttentionEvent.from(transition: .working, to: .blockedByAutoMode)
                == .blockedByAutoMode
        )
    }

    @Test("Entering errored maps to errored")
    func errored() {
        #expect(
            AttentionEvent.from(transition: .working, to: .errored(reason: "boom"))
                == .errored
        )
    }

    @Test("working → idle is finishedOutputting (claude's turn ended)")
    func finishedOutputting() {
        #expect(
            AttentionEvent.from(transition: .working, to: .idle)
                == .finishedOutputting
        )
    }

    @Test("starting → idle is not finishedOutputting (initial settle, not a turn)")
    func startingToIdleIsNotFinishedOutputting() {
        #expect(AttentionEvent.from(transition: .starting, to: .idle) == nil)
    }

    @Test("Recovering from an attention state to idle is not finishedOutputting")
    func attentionToIdleIsNotFinishedOutputting() {
        #expect(AttentionEvent.from(transition: .waitingForPermission, to: .idle) == nil)
        #expect(AttentionEvent.from(transition: .waitingForIdle, to: .idle) == nil)
        #expect(AttentionEvent.from(transition: .blockedByAutoMode, to: .idle) == nil)
    }

    @Test("Entering stopped maps to stopped, regardless of source state")
    func stopped() {
        #expect(AttentionEvent.from(transition: .working, to: .stopped) == .stopped)
        #expect(AttentionEvent.from(transition: .idle, to: .stopped) == .stopped)
        #expect(AttentionEvent.from(transition: .errored(reason: "x"), to: .stopped) == .stopped)
    }

    @Test("Transitions that just resume work don't fire an event")
    func resumingWorkIsSilent() {
        #expect(AttentionEvent.from(transition: .idle, to: .working) == nil)
        #expect(AttentionEvent.from(transition: .waitingForPermission, to: .working) == nil)
        #expect(AttentionEvent.from(transition: .starting, to: .working) == nil)
    }
}
