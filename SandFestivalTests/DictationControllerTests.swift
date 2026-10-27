import Foundation
import Testing
@testable import SandFestival

@MainActor
@Suite("DictationController")
struct DictationControllerTests {

    @Test("pastes the finalized transcript with a trailing space when the engine ends")
    func pastesOnEnd() async {
        let engine = StubSpeechEngine(
            script: [
                .result(text: "Refactor the", isFinal: false, rangeEnd: 1),
                .result(text: "Refactor the session.", isFinal: true, rangeEnd: 2),
            ],
            endsAfterScript: true
        )
        let (controller, target) = makeController(engine: engine)

        controller.toggle(for: target)
        await controller.runTask?.value

        #expect(target.inserted == ["Refactor the session. "])
        #expect(controller.phase == .idle)
        #expect(controller.targetID == nil)
    }

    @Test("toggling while listening finishes and pastes")
    func toggleFinishes() async {
        let engine = StubSpeechEngine(script: [.result(text: "hello", isFinal: true, rangeEnd: 1)])
        let (controller, target) = makeController(engine: engine)
        controller.toggle(for: target)
        await waitUntil { controller.phase == .listening && controller.transcript.text == "hello" }

        controller.toggle(for: target)
        await controller.runTask?.value

        #expect(await engine.finishCalls == 1)
        #expect(target.inserted == ["hello "])
    }

    @Test("holds the text when the session isn't ready for a prompt")
    func holdsWhenNotReady() async {
        let engine = StubSpeechEngine(
            script: [.result(text: "yes do it", isFinal: true, rangeEnd: 1)],
            endsAfterScript: true
        )
        let (controller, target) = makeController(engine: engine)
        target.isReadyForDictation = false

        controller.toggle(for: target)
        await controller.runTask?.value

        #expect(target.inserted.isEmpty)
        #expect(controller.phase == .held("yes do it"))
        #expect(controller.targetID == target.id)
    }

    @Test("pasting held text inserts it and resets")
    func pasteHeld() async {
        let engine = StubSpeechEngine(
            script: [.result(text: "yes do it", isFinal: true, rangeEnd: 1)],
            endsAfterScript: true
        )
        let (controller, target) = makeController(engine: engine)
        target.isReadyForDictation = false
        controller.toggle(for: target)
        await controller.runTask?.value

        controller.pasteHeldText()

        #expect(target.inserted == ["yes do it "])
        #expect(controller.phase == .idle)
    }

    @Test("an empty transcript pastes nothing")
    func emptyPastesNothing() async {
        let engine = StubSpeechEngine(script: [.audioAdvanced(to: 1)], endsAfterScript: true)
        let (controller, target) = makeController(engine: engine)

        controller.toggle(for: target)
        await controller.runTask?.value

        #expect(target.inserted.isEmpty)
        #expect(controller.phase == .idle)
    }

    @Test("discarding while listening cancels the engine and pastes nothing")
    func discardCancels() async {
        let engine = StubSpeechEngine(script: [.result(text: "never mind", isFinal: false, rangeEnd: 1)])
        let (controller, target) = makeController(engine: engine)
        controller.toggle(for: target)
        await waitUntil { controller.phase == .listening && !controller.transcript.isEmpty }
        let run = controller.runTask

        controller.discard()
        await run?.value
        await waitUntil { await engine.cancelCalls > 0 }

        #expect(target.inserted.isEmpty)
        #expect(controller.phase == .idle)
        #expect(controller.transcript.isEmpty)
        #expect(await engine.cancelCalls >= 1)
    }

    @Test("a denied microphone fails with a route to privacy settings")
    func microphoneDenied() async {
        let engine = StubSpeechEngine(prepareError: .microphoneDenied)
        let (controller, target) = makeController(engine: engine)

        controller.toggle(for: target)
        await controller.runTask?.value

        guard case .failed(_, let offersPrivacySettings) = controller.phase else {
            Issue.record("expected failure, got \(controller.phase)")
            return
        }
        #expect(offersPrivacySettings)
        #expect(target.inserted.isEmpty)
    }

    @Test("another session can't start dictation while one is busy")
    func busyBlocksOtherTargets() async {
        let engine = StubSpeechEngine()
        let (controller, target) = makeController(engine: engine)
        let other = StubDictationTarget()
        controller.toggle(for: target)
        await waitUntil { controller.phase == .listening }

        controller.toggle(for: other)

        #expect(controller.targetID == target.id)
        #expect(!controller.canToggle(for: other.id))
        #expect(controller.canToggle(for: target.id))
        controller.discard()
    }

    @Test("finishes on its own after the silence timeout and pastes")
    func autoFinishesAfterSilence() async {
        let engine = StubSpeechEngine(script: [
            .audioAdvanced(to: 1),
            .result(text: "hello there", isFinal: true, rangeEnd: 1),
            .audioAdvanced(to: 2),
            .audioAdvanced(to: 3.6),
        ])
        let (controller, target) = makeController(engine: engine)

        controller.toggle(for: target)
        await waitUntil { await engine.finishCalls > 0 }
        await controller.runTask?.value

        #expect(await engine.finishCalls == 1)
        #expect(target.inserted == ["hello there "])
    }

    @Test("punctuation arriving after speech doesn't extend listening")
    func punctuationDoesNotExtend() async {
        let engine = StubSpeechEngine(script: [
            .result(text: "hello there", isFinal: false, rangeEnd: 1),
            .audioAdvanced(to: 2),
            .result(text: "Hello there.", isFinal: false, rangeEnd: 2),
            .audioAdvanced(to: 3.6),
        ])
        let (controller, target) = makeController(engine: engine)

        controller.toggle(for: target)
        await waitUntil { await engine.finishCalls > 0 }

        #expect(await engine.finishCalls == 1)
        controller.discard()
    }

    @Test("keeps listening while words keep arriving")
    func keepsListeningDuringSpeech() async {
        let engine = StubSpeechEngine(script: [
            .result(text: "one", isFinal: false, rangeEnd: 1),
            .audioAdvanced(to: 3),
            .result(text: "one two", isFinal: false, rangeEnd: 3),
            .audioAdvanced(to: 5),
            .result(text: "one two three", isFinal: false, rangeEnd: 5),
            .audioAdvanced(to: 7),
        ])
        let (controller, target) = makeController(engine: engine)

        controller.toggle(for: target)
        await waitUntil { controller.transcript.text == "one two three" }

        #expect(controller.phase == .listening)
        #expect(await engine.finishCalls == 0)
        controller.discard()
    }

    @Test("stops without pasting when nothing is said")
    func discardsWhenSilent() async {
        let engine = StubSpeechEngine(script: [.audioAdvanced(to: 4), .audioAdvanced(to: 8)])
        let (controller, target) = makeController(engine: engine)

        controller.toggle(for: target)
        await waitUntil { await engine.cancelCalls > 0 }

        #expect(controller.phase == .idle)
        #expect(target.inserted.isEmpty)
    }

    @Test("uses the configured silence timeout")
    func configuredTimeout() async {
        let engine = StubSpeechEngine(script: [
            .result(text: "hello", isFinal: true, rangeEnd: 1),
            .audioAdvanced(to: 3.6),
        ])
        let (controller, target) = makeController(engine: engine)
        controller.endpointConfigurationProvider = { .init(silenceTimeout: 4) }

        controller.toggle(for: target)
        await waitUntil { controller.endpointer.audioTime == 3.6 }

        #expect(controller.phase == .listening)
        #expect(await engine.finishCalls == 0)
        controller.discard()
    }

    @Test("tracks the microphone level while listening and resets afterwards")
    func tracksMicrophoneLevel() async {
        let engine = StubSpeechEngine(script: [.inputLevel(rms: 1)])
        let (controller, target) = makeController(engine: engine)

        controller.toggle(for: target)
        await waitUntil { controller.inputLevel == 1 }
        #expect(controller.inputLevel == 1)

        controller.discard()
        #expect(controller.inputLevel == 0)
    }

    @Test("held text blocks every session's mic until it's pasted, copied or discarded")
    func heldTextBlocksNewDictation() async {
        let engine = StubSpeechEngine(
            script: [.result(text: "yes do it", isFinal: true, rangeEnd: 1)],
            endsAfterScript: true
        )
        let (controller, target) = makeController(engine: engine)
        let other = StubDictationTarget()
        target.isReadyForDictation = false
        controller.toggle(for: target)
        await controller.runTask?.value

        controller.toggle(for: other)
        controller.toggle(for: target)

        #expect(controller.phase == .held("yes do it"))
        #expect(controller.isHoldingText)
        #expect(!controller.canToggle(for: other.id))
        #expect(!controller.canToggle(for: target.id))
        controller.pasteHeldText()
        #expect(controller.canToggle(for: other.id))
    }

    @Test("held text for a session that no longer exists doesn't block")
    func heldTextForRemovedSessionDoesNotBlock() async {
        let engine = StubSpeechEngine(
            script: [.result(text: "yes do it", isFinal: true, rangeEnd: 1)],
            endsAfterScript: true
        )
        let controller = DictationController(makeEngine: { engine })
        var target: StubDictationTarget? = StubDictationTarget()
        target?.isReadyForDictation = false
        controller.toggle(for: target!)
        await controller.runTask?.value

        target = nil

        #expect(!controller.isHoldingText)
        #expect(controller.canToggle(for: StubDictationTarget().id))
    }

    @Test("dictation for a session that was removed is discarded on the next audio")
    func removedSessionDiscards() async {
        let engine = StubSpeechEngine(script: [.result(text: "hello", isFinal: false, rangeEnd: 1)])
        let controller = DictationController(makeEngine: { engine })
        var target: StubDictationTarget? = StubDictationTarget()
        controller.toggle(for: target!)
        await waitUntil { controller.transcript.text == "hello" }

        target = nil
        await engine.emit(.audioAdvanced(to: 1.1))
        await waitUntil { await engine.cancelCalls > 0 }

        #expect(controller.phase == .idle)
        #expect(controller.targetID == nil)
        #expect(await engine.cancelCalls >= 1)
    }

    @Test("the mic during clean-up skips it and pastes the raw transcript")
    func toggleDuringCleanupSkips() async {
        let engine = StubSpeechEngine(
            script: [.result(text: "fix the swift term view", isFinal: true, rangeEnd: 1)],
            endsAfterScript: true
        )
        let (controller, target) = makeController(engine: engine, refiner: StubRefiner(output: nil))
        controller.toggle(for: target)
        await waitUntil { controller.phase == .refining }

        #expect(controller.canToggle(for: target.id))
        controller.toggle(for: target)
        await controller.runTask?.value

        #expect(target.inserted == ["fix the swift term view "])
    }

    @Test("Skip doesn't wait for a clean-up that ignores cancellation")
    func skipDoesNotWaitForStuckRefiner() async {
        let engine = StubSpeechEngine(
            script: [.result(text: "fix the swift term view", isFinal: true, rangeEnd: 1)],
            endsAfterScript: true
        )
        let refiner = StubRefiner(output: nil, ignoresCancellation: true)
        let (controller, target) = makeController(engine: engine, refiner: refiner)
        controller.toggle(for: target)
        await waitUntil { controller.phase == .refining }

        controller.skipRefinement()
        await controller.runTask?.value

        #expect(target.inserted == ["fix the swift term view "])
        refiner.release()
    }

    @Test("the timeout doesn't wait for a clean-up that ignores cancellation")
    func timeoutDoesNotWaitForStuckRefiner() async {
        let engine = StubSpeechEngine(
            script: [.result(text: "fix the swift term view", isFinal: true, rangeEnd: 1)],
            endsAfterScript: true
        )
        let refiner = StubRefiner(output: nil, timeout: .milliseconds(50), ignoresCancellation: true)
        let (controller, target) = makeController(engine: engine, refiner: refiner)

        controller.toggle(for: target)
        await controller.runTask?.value

        #expect(target.inserted == ["fix the swift term view "])
        refiner.release()
    }

    @Test("finishes with what it has when audio stops arriving")
    func finishesWhenAudioStalls() async {
        let engine = StubSpeechEngine(script: [
            .audioAdvanced(to: 0.5),
            .result(text: "hello", isFinal: true, rangeEnd: 0.5),
        ])
        let (controller, target) = makeController(engine: engine)
        controller.endpointConfigurationProvider = { .init(audioStallTimeout: 0.2) }

        controller.toggle(for: target)
        await waitUntil { await engine.finishCalls > 0 }
        await controller.runTask?.value

        #expect(target.inserted == ["hello "])
    }

    @Test("cleans up the transcript with the project vocabulary before pasting")
    func refinesBeforePasting() async {
        let engine = StubSpeechEngine(
            script: [.result(text: "um fix the swift term view", isFinal: true, rangeEnd: 1)],
            endsAfterScript: true
        )
        let refiner = StubRefiner(output: .success("Fix the SwiftTerm view."))
        let (controller, target) = makeController(engine: engine, refiner: refiner)
        target.vocabulary = ["SwiftTerm"]

        controller.toggle(for: target)
        await controller.runTask?.value

        #expect(target.inserted == ["Fix the SwiftTerm view. "])
        #expect(refiner.calls == [.init(transcript: "um fix the swift term view", vocabulary: ["SwiftTerm"])])
    }

    @Test("pastes the raw transcript when clean-up fails")
    func fallsBackOnFailure() async {
        let engine = StubSpeechEngine(
            script: [.result(text: "fix the swift term view", isFinal: true, rangeEnd: 1)],
            endsAfterScript: true
        )
        let (controller, target) = makeController(
            engine: engine,
            refiner: StubRefiner(output: .failure(.unavailable))
        )

        controller.toggle(for: target)
        await controller.runTask?.value

        #expect(target.inserted == ["fix the swift term view "])
    }

    @Test("pastes the raw transcript when the clean-up answers instead")
    func rejectsImplausibleCleanup() async {
        let engine = StubSpeechEngine(
            script: [.result(text: "how do I fix this", isFinal: true, rangeEnd: 1)],
            endsAfterScript: true
        )
        let answer = "To fix this, first check the logs, then reproduce the failure in a test, and finally bisect the recent commits."
        let (controller, target) = makeController(engine: engine, refiner: StubRefiner(output: .success(answer)))

        controller.toggle(for: target)
        await controller.runTask?.value

        #expect(target.inserted == ["how do I fix this "])
    }

    @Test("skipping clean-up pastes the raw transcript right away")
    func skipPastesRaw() async {
        let engine = StubSpeechEngine(
            script: [.result(text: "fix the swift term view", isFinal: true, rangeEnd: 1)],
            endsAfterScript: true
        )
        let (controller, target) = makeController(engine: engine, refiner: StubRefiner(output: nil))
        controller.toggle(for: target)
        await waitUntil { controller.phase == .refining }

        controller.skipRefinement()
        await controller.runTask?.value

        #expect(target.inserted == ["fix the swift term view "])
        #expect(controller.phase == .idle)
    }

    @Test("a clean-up that outlives its timeout falls back to the raw transcript")
    func timeoutFallsBack() async {
        let engine = StubSpeechEngine(
            script: [.result(text: "fix the swift term view", isFinal: true, rangeEnd: 1)],
            endsAfterScript: true
        )
        let (controller, target) = makeController(
            engine: engine,
            refiner: StubRefiner(output: nil, timeout: .milliseconds(50))
        )

        controller.toggle(for: target)
        await controller.runTask?.value

        #expect(target.inserted == ["fix the swift term view "])
    }

    @Test("held text is the cleaned-up transcript")
    func holdsCleanedText() async {
        let engine = StubSpeechEngine(
            script: [.result(text: "um yes do it", isFinal: true, rangeEnd: 1)],
            endsAfterScript: true
        )
        let (controller, target) = makeController(engine: engine, refiner: StubRefiner(output: .success("Yes, do it.")))
        target.isReadyForDictation = false

        controller.toggle(for: target)
        await controller.runTask?.value

        #expect(controller.phase == .held("Yes, do it."))
    }

    private func makeController(
        engine: StubSpeechEngine,
        refiner: StubRefiner? = nil
    ) -> (DictationController, StubDictationTarget) {
        let controller = DictationController(makeEngine: { engine })
        if let refiner {
            controller.refinerProvider = { refiner }
        }
        return (controller, StubDictationTarget())
    }

    private func waitUntil(_ condition: () async -> Bool) async {
        for _ in 0..<1000 {
            if await condition() { return }
            try? await Task.sleep(for: .milliseconds(2))
        }
    }
}

@MainActor
private final class StubDictationTarget: DictationTarget {
    let id = UUID()
    var isReadyForDictation = true
    var canReceiveText = true
    var vocabulary: [String] = []
    private(set) var inserted: [String] = []

    func insertDictatedText(_ text: String) {
        inserted.append(text)
    }

    func dictationVocabulary() async -> [String] {
        vocabulary
    }
}

private final class StubRefiner: TranscriptRefiner, @unchecked Sendable {
    struct Call: Equatable {
        let transcript: String
        let vocabulary: [String]
    }

    private let output: Result<String, TranscriptRefinerError>?
    let timeout: Duration
    private let ignoresCancellation: Bool
    private let lock = NSLock()
    private var recorded: [Call] = []
    private var stuck: [CheckedContinuation<Void, Never>] = []
    private var released = false

    var calls: [Call] {
        lock.withLock { recorded }
    }

    init(
        output: Result<String, TranscriptRefinerError>?,
        timeout: Duration = .seconds(30),
        ignoresCancellation: Bool = false
    ) {
        self.output = output
        self.timeout = timeout
        self.ignoresCancellation = ignoresCancellation
    }

    func refine(_ transcript: String, vocabulary: [String]) async throws -> String {
        lock.withLock { recorded.append(Call(transcript: transcript, vocabulary: vocabulary)) }
        guard let output else {
            if ignoresCancellation {
                await withCheckedContinuation { continuation in
                    let resumeNow = lock.withLock {
                        if released { return true }
                        stuck.append(continuation)
                        return false
                    }
                    if resumeNow { continuation.resume() }
                }
                return "too late"
            }
            try await Task.sleep(for: .seconds(60))
            throw CancellationError()
        }
        return try output.get()
    }

    func release() {
        let continuations = lock.withLock {
            released = true
            defer { stuck = [] }
            return stuck
        }
        continuations.forEach { $0.resume() }
    }
}

private actor StubSpeechEngine: SpeechEngine {
    private let script: [SpeechEngineEvent]
    private let endsAfterScript: Bool
    private let prepareError: DictationError?
    private var continuation: AsyncThrowingStream<SpeechEngineEvent, any Error>.Continuation?
    private(set) var finishCalls = 0
    private(set) var cancelCalls = 0

    init(script: [SpeechEngineEvent] = [], endsAfterScript: Bool = false, prepareError: DictationError? = nil) {
        self.script = script
        self.endsAfterScript = endsAfterScript
        self.prepareError = prepareError
    }

    func prepare(onProgress: @escaping @Sendable (Double) -> Void) async throws {
        if let prepareError { throw prepareError }
    }

    func start() async throws -> AsyncThrowingStream<SpeechEngineEvent, any Error> {
        let (stream, continuation) = AsyncThrowingStream<SpeechEngineEvent, any Error>.makeStream()
        for event in script {
            continuation.yield(event)
        }
        if endsAfterScript {
            continuation.finish()
        } else {
            self.continuation = continuation
        }
        return stream
    }

    func emit(_ event: SpeechEngineEvent) {
        continuation?.yield(event)
    }

    func finish() async {
        finishCalls += 1
        continuation?.finish()
    }

    func cancel() async {
        cancelCalls += 1
        continuation?.finish()
    }
}
