import Testing
@testable import SandFestival

@Suite("TurnSummary")
struct TurnSummaryTests {

    @Test("the prompt wraps the reply")
    func promptWrapsReply() {
        #expect(TurnSummary.prompt(message: "Done.") == "<reply>Done.</reply>")
    }

    @Test("a reply that ends with a question says so in the prompt")
    func promptFlagsClosingQuestion() {
        #expect(TurnSummary.prompt(message: "Which do you prefer?") == "<reply>Which do you prefer?</reply>\nThe reply ends by asking the developer a question.")
    }

    @Test("only the last prose line decides whether the reply ends with a question")
    func closingQuestionDetection() {
        #expect(TurnSummary.endsWithQuestion("Done.\nWant me to update the docs?"))
        #expect(!TurnSummary.endsWithQuestion("Why did it fail? The token raced the bind. Fixed now."))
        #expect(!TurnSummary.endsWithQuestion("Fixed it.\n```swift\nlet ok = a ? b : c\n```"))
    }

    @Test("a reply within the limit is passed whole")
    func shortReplyUntouched() {
        #expect(TurnSummary.excerpt("abcdef", limit: 6) == "abcdef")
    }

    @Test("a long reply keeps its opening and its closing question")
    func longReplyKeepsHeadAndTail() {
        let message = String(repeating: "a", count: 100) + String(repeating: "b", count: 100) + "Which do you prefer?"
        let excerpt = TurnSummary.excerpt(message, limit: 60)

        #expect(excerpt.hasPrefix(String(repeating: "a", count: 40)))
        #expect(excerpt.hasSuffix("Which do you prefer?"))
        #expect(excerpt.contains("\n…\n"))
    }

    @Test("a status line is accepted with label, quotes and line breaks removed")
    func acceptsCleanedStatus() {
        #expect(TurnSummary.accept("  Output: “Fixed the race;\nall tests pass”\n") == "Fixed the race; all tests pass")
    }

    @Test("an empty or overlong status is rejected")
    func rejectsEmptyOrLong() {
        #expect(TurnSummary.accept("  \n") == nil)
        #expect(TurnSummary.accept(String(repeating: "word ", count: 60)) == nil)
    }

    @Test("the fallback is the first line with words, skipping headings and markdown")
    func fallbackSkipsMarkdown() {
        let message = """
            ## Summary

            ---
            - **Fixed** the `HookListener` race
            - Added a test
            """

        #expect(TurnSummary.fallback(from: message) == "Fixed the HookListener race")
    }

    @Test("the fallback skips fenced code")
    func fallbackSkipsCode() {
        let message = """
            ```swift
            let x = 1
            ```
            That's the change.
            """

        #expect(TurnSummary.fallback(from: message) == "That's the change.")
    }

    @Test("a reply without words has no fallback")
    func fallbackNeedsWords() {
        #expect(TurnSummary.fallback(from: "---\n\n```\n```") == nil)
    }
}
