import Testing
@testable import SandFestival

@Suite("DictationEndpointer")
struct DictationEndpointerTests {

    @Test("finishes once silence after the last speech reaches the timeout")
    func finishesAfterSilence() {
        var endpointer = DictationEndpointer()
        endpointer.speechObserved(through: 6.84)

        endpointer.audioAdvanced(to: 9.3)
        #expect(endpointer.decision == .listening)

        endpointer.audioAdvanced(to: 9.34)
        #expect(endpointer.decision == .finish)
    }

    @Test("a mid-sentence pause shorter than the timeout keeps listening")
    func shortPauseKeepsListening() {
        var endpointer = DictationEndpointer()
        for (speech, audio) in [(2.0, 2.0), (3.0, 3.0), (4.0, 4.0), (4.9, 4.9), (5.9, 5.9), (6.8, 6.8)] {
            endpointer.speechObserved(through: speech)
            endpointer.audioAdvanced(to: audio)
            #expect(endpointer.decision == .listening)
        }
    }

    @Test("the probe timeline ends 2.5 s after the finalized speech end, not the trailing punctuation")
    func probeTimeline() {
        var endpointer = DictationEndpointer()
        for time in [2.0, 3.0, 4.0, 4.9, 5.9, 6.8] {
            endpointer.audioAdvanced(to: time)
            endpointer.speechObserved(through: time)
        }
        endpointer.audioAdvanced(to: 7.8)
        endpointer.audioAdvanced(to: 8.1)
        endpointer.speechObserved(through: 6.84)

        endpointer.audioAdvanced(to: 9.33)
        #expect(endpointer.decision == .listening)
        endpointer.audioAdvanced(to: 9.35)
        #expect(endpointer.decision == .finish)
    }

    @Test("discards when nothing is said before the no-speech timeout")
    func discardsWithoutSpeech() {
        var endpointer = DictationEndpointer()

        endpointer.audioAdvanced(to: 7.9)
        #expect(endpointer.decision == .listening)

        endpointer.audioAdvanced(to: 8)
        #expect(endpointer.decision == .discardNoSpeech)
    }

    @Test("finishes at the maximum duration even while speech continues")
    func capsDuration() {
        var endpointer = DictationEndpointer(configuration: .init(maximumDuration: 60))

        endpointer.speechObserved(through: 60)
        endpointer.audioAdvanced(to: 60)

        #expect(endpointer.decision == .finish)
    }

    @Test("speech and audio times never move backwards")
    func monotonic() {
        var endpointer = DictationEndpointer()
        endpointer.speechObserved(through: 5)
        endpointer.audioAdvanced(to: 6)

        endpointer.speechObserved(through: 4)
        endpointer.audioAdvanced(to: 1)

        #expect(endpointer.lastSpeech == 5)
        #expect(endpointer.audioTime == 6)
    }

    @Test("the silence timeout is configurable")
    func configurableTimeout() {
        var endpointer = DictationEndpointer(configuration: .init(silenceTimeout: 1.5))
        endpointer.speechObserved(through: 1)

        endpointer.audioAdvanced(to: 2.5)

        #expect(endpointer.decision == .finish)
    }
}
