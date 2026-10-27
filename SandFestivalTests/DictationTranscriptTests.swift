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

    @Test("words ignore punctuation and case")
    func wordsIgnorePunctuation() {
        var transcript = DictationTranscript()
        transcript.apply(text: "it keeps the hook listener alive after a restart", isFinal: false)
        let before = transcript.words

        transcript.apply(text: "It keeps the hook listener alive after a restart.", isFinal: false)

        #expect(transcript.words == before)
        #expect(before.first == "it")
    }

    @Test("whitespace-only results leave the transcript empty")
    func whitespaceIsEmpty() {
        var transcript = DictationTranscript()

        transcript.apply(text: "  ", isFinal: true)

        #expect(transcript.isEmpty)
    }

    @Test("a slash command loses the punctuation dictation adds")
    func slashCommandPunctuation() {
        #expect(DictationTranscript.prompt(from: "/clear.") == "/clear")
        #expect(DictationTranscript.prompt(from: "/model haiku!") == "/model haiku")
        #expect(DictationTranscript.prompt(from: "/compact focus on the tests…") == "/compact focus on the tests")
    }

    @Test("a spoken slash at the start becomes a slash command")
    func spokenSlash() {
        #expect(DictationTranscript.prompt(from: "Slash clear.") == "/clear")
        #expect(DictationTranscript.prompt(from: "slash, compact focus on the tests.") == "/compact focus on the tests")
        #expect(DictationTranscript.prompt(from: "/ clear.") == "/clear")
    }

    @Test("slash only counts as a command at the start, as its own word")
    func slashInProse() {
        #expect(DictationTranscript.prompt(from: "Slashing the timeout broke it.") == "Slashing the timeout broke it.")
        #expect(DictationTranscript.prompt(from: "Add a slash route.") == "Add a slash route.")
    }

    @Test("a prose prompt keeps its punctuation")
    func prosePunctuation() {
        #expect(DictationTranscript.prompt(from: "Run the tests.") == "Run the tests.")
        #expect(DictationTranscript.prompt(from: "Why does /clear fail?") == "Why does /clear fail?")
    }
}
