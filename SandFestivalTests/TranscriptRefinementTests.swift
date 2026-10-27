import Testing
@testable import SandFestival

@Suite("TranscriptRefinement")
struct TranscriptRefinementTests {

    @Test("the prompt tags vocabulary and transcript")
    func promptWithVocabulary() {
        let prompt = TranscriptRefinement.prompt(transcript: "fix the swift term view", vocabulary: ["SwiftTerm", "nono"])

        #expect(prompt == "<vocabulary>SwiftTerm, nono</vocabulary>\n<transcript>fix the swift term view</transcript>")
    }

    @Test("an empty vocabulary is left out of the prompt")
    func promptWithoutVocabulary() {
        #expect(TranscriptRefinement.prompt(transcript: "hello", vocabulary: []) == "<transcript>hello</transcript>")
    }

    @Test("a cleaned transcript with fillers removed is accepted")
    func acceptsFillerRemoval() {
        let original = "Um so can you uh can you look at why the swift term view loses the selection when uh output streams in"
        let refined = "Can you look at why the SwiftTerm view loses the selection when output streams in?"

        #expect(TranscriptRefinement.accept(refined, original: original) == refined)
    }

    @Test("surrounding quotes, tags and whitespace are stripped")
    func stripsWrapping() {
        #expect(TranscriptRefinement.accept("  “Refactor the SessionManager.”\n", original: "refactor the session manager") == "Refactor the SessionManager.")
        #expect(TranscriptRefinement.accept("<transcript>Hello there.</transcript>", original: "hello there") == "Hello there.")
    }

    @Test("a copied Output: label is stripped")
    func stripsOutputLabel() {
        #expect(TranscriptRefinement.accept("Output: Delete the UserService tests.", original: "delete the user service tests") == "Delete the UserService tests.")
    }

    @Test("the reply budget scales with the transcript and has a floor")
    func responseBudget() {
        #expect(TranscriptRefinement.maximumResponseTokens(for: "yes") == 64)
        let long = Array(repeating: "word", count: 100).joined(separator: " ")
        #expect(TranscriptRefinement.maximumResponseTokens(for: long) == 300)
    }

    @Test("an answer instead of a clean-up is rejected")
    func rejectsAnswers() {
        let original = "What's the best way to handle errors here?"
        let answer = "The best way to handle errors here is to use Swift's do-catch blocks and propagate typed errors to the caller so the UI can present them."

        #expect(TranscriptRefinement.accept(answer, original: original) == nil)
    }

    @Test("an empty or drastically shortened result is rejected")
    func rejectsTruncation() {
        let original = "please rename the hook listener port constant and update every test that references it"

        #expect(TranscriptRefinement.accept("", original: original) == nil)
        #expect(TranscriptRefinement.accept("Rename it.", original: original) == nil)
    }

    @Test("short dictations tolerate a few added words")
    func shortInputsTolerateSmallChanges() {
        #expect(TranscriptRefinement.accept("Yes, go ahead with that.", original: "yes go ahead") == "Yes, go ahead with that.")
    }

    @Test("vocabulary keeps distinctive names, shallow paths first, project name leading")
    func vocabularyPicksDistinctiveTerms() {
        let files = [
            "SandFestival/Core/SessionManager.swift",
            "README.md",
            "scripts/release.sh",
            "Packages/SwiftTermMacOS/Package.swift",
            "web/src/use-session-state.ts",
            "SandFestival/Core/SessionManager.swift",
        ]

        let vocabulary = TranscriptRefinement.vocabulary(projectName: "Sand Festival", trackedFiles: files)

        #expect(vocabulary == ["Sand Festival", "SwiftTermMacOS", "SandFestival", "SessionManager", "use-session-state"])
    }

    @Test("vocabulary respects the limit")
    func vocabularyLimit() {
        let files = (0..<50).map { "Sources/TypeNumber\($0)View.swift" }

        let vocabulary = TranscriptRefinement.vocabulary(projectName: "App", trackedFiles: files, limit: 10)

        #expect(vocabulary.count == 10)
        #expect(vocabulary.first == "App")
    }
}
