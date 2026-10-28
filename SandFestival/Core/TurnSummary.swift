import Foundation

nonisolated protocol TurnSummarizer: Sendable {
    var timeout: Duration { get }
    func summarize(_ message: String) async throws -> String
}

nonisolated enum TurnSummarizerError: Error, Equatable {
    case unavailable
}

nonisolated enum TurnSummary {
    static let instructions = """
        You write the status line a developer sees after their AI coding assistant finishes a turn. \
        <reply> holds the assistant's last message. In at most 10 words, tell the developer the one thing they most need to know:
        - If the reply asks the developer anything or offers to do more, start with "Asks" and say what it asks.
        - If the reply says something failed or is blocked, start with "Blocked:" and say what.
        - If the reply reports finished work, start with a past-tense verb and say what was done.
        - If the reply only explains or answers, start with "Explained" and say what.
        Write your own words; never copy a sentence from the reply. Never mention work the reply does not mention.

        Example
        <reply>I fixed the flaky test in HookListenerTests. The listener was bound before the token loaded, so the \
        first request raced it. I moved the bind after loadOrCreate(). All 42 tests pass now.</reply>
        Output: Fixed the HookListenerTests race; all tests pass

        Example
        <reply>I renamed the setting and updated both call sites. There are two ways to migrate existing values: \
        rewrite them in place, or keep the old key as a fallback. Which would you prefer?</reply>
        Output: Asks how to migrate existing values of the renamed setting

        Example
        <reply>The release build fails at notarization: notarytool reports "Invalid credentials". I can't fix this \
        from here; the API key in NOTARY_KEY_PATH needs to be regenerated.</reply>
        Output: Blocked: notarization rejects the API key

        Example
        <reply>Sessions are stored in projects.json under Application Support. SessionManager loads it at launch \
        and writes it back after a one-second debounce.</reply>
        Output: Explained how sessions are stored and saved
        """

    static let messageCharacterLimit = 6_000
    static let summaryCharacterLimit = 200
    static let maximumResponseTokens = 64

    static func prompt(message: String) -> String {
        let reply = "<reply>\(excerpt(message, limit: messageCharacterLimit))</reply>"
        guard endsWithQuestion(message) else { return reply }
        return "\(reply)\nThe reply ends by asking the developer a question."
    }

    static func endsWithQuestion(_ message: String) -> Bool {
        proseLines(message).last?.hasSuffix("?") ?? false
    }

    static func excerpt(_ message: String, limit: Int) -> String {
        guard message.count > limit else { return message }
        let tailLength = limit / 3
        return "\(message.prefix(limit - tailLength))\n…\n\(message.suffix(tailLength))"
    }

    static func accept(_ summary: String) -> String? {
        let unlabeled = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleaned = (unlabeled.hasPrefix("Output:") ? String(unlabeled.dropFirst("Output:".count)) : unlabeled)
            .split(whereSeparator: \.isNewline)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"“”"))
            .trimmingCharacters(in: .whitespaces)
        guard !cleaned.isEmpty, cleaned.count <= summaryCharacterLimit else { return nil }
        return cleaned
    }

    static func fallback(from message: String) -> String? {
        proseLines(message).first
    }

    private static func proseLines(_ message: String) -> [String] {
        var insideFence = false
        var lines: [String] = []
        for line in message.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                insideFence.toggle()
                continue
            }
            guard !insideFence, !trimmed.hasPrefix("#") else { continue }
            let plain = plainText(trimmed)
            if plain.contains(where: \.isLetter) { lines.append(plain) }
        }
        return lines
    }

    private static func plainText(_ line: String) -> String {
        String(line.drop { ">*-+ ".contains($0) })
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "`", with: "")
            .trimmingCharacters(in: .whitespaces)
    }
}
