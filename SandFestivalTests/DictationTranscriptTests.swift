import Testing
@testable import SandFestival

@Suite("DictationTranscript")
struct DictationTranscriptTests {

    @Test("a volatile result replaces the previous one")
    func volatileReplaces() {
        var transcript = DictationTranscript()

        transcript.apply(text: "We fact", isFinal: false)
        transcript.apply(text: "We factor the", isFinal: false)

        #expect(transcript.text == "We factor the")
        #expect(transcript.finalizedText.isEmpty)
    }

    @Test("a final result commits and clears the volatile text")
    func finalCommits() {
        var transcript = DictationTranscript()
        transcript.apply(text: "Refactor the", isFinal: false)

        transcript.apply(text: "Refactor the session.", isFinal: true)

        #expect(transcript.finalizedText == "Refactor the session.")
        #expect(transcript.volatileText.isEmpty)
        #expect(transcript.text == "Refactor the session.")
    }

    @Test("segments without whitespace at the seam are joined with a space")
    func joinsWithSpace() {
        var transcript = DictationTranscript()

        transcript.apply(text: "First sentence.", isFinal: true)
        transcript.apply(text: "Second", isFinal: true)

        #expect(transcript.text == "First sentence. Second")
    }

    @Test("segments that already carry whitespace are not double-spaced")
    func keepsExistingWhitespace() {
        var transcript = DictationTranscript()

        transcript.apply(text: "First sentence.", isFinal: true)
        transcript.apply(text: " Second", isFinal: true)

        #expect(transcript.text == "First sentence. Second")
    }

    @Test("the volatile suffix carries the separator after the finalized text")
    func volatileSuffixIncludesSeparator() {
        var transcript = DictationTranscript()
        transcript.apply(text: "Done.", isFinal: true)

        transcript.apply(text: "Next", isFinal: false)

        #expect(transcript.volatileSuffix == " Next")
        #expect(transcript.finalizedText + transcript.volatileSuffix == "Done. Next")
    }

    @Test("whitespace-only results leave the transcript empty")
    func whitespaceIsEmpty() {
        var transcript = DictationTranscript()

        transcript.apply(text: "  ", isFinal: true)

        #expect(transcript.isEmpty)
    }
}
