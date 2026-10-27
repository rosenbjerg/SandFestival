import Foundation

nonisolated struct DictationTranscript: Equatable, Sendable {
    private(set) var finalizedText = ""
    private(set) var volatileText = ""

    mutating func apply(text: String, isFinal: Bool) {
        if isFinal {
            finalizedText = Self.join(finalizedText, text)
            volatileText = ""
        } else {
            volatileText = text
        }
    }

    var text: String {
        Self.join(finalizedText, volatileText).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var volatileSuffix: String {
        String(Self.join(finalizedText, volatileText).dropFirst(finalizedText.count))
    }

    var isEmpty: Bool { text.isEmpty }

    var words: [String] {
        Self.words(in: text)
    }

    static func words(in text: String) -> [String] {
        text.split { !($0.isLetter || $0.isNumber) }.map { $0.lowercased() }
    }

    static func prompt(from text: String) -> String {
        guard text.hasPrefix("/") else { return text }
        var command = Substring(text)
        while let last = command.last, last.isWhitespace || ".,;:!?…".contains(last) {
            command = command.dropLast()
        }
        return String(command)
    }

    private static func join(_ head: String, _ tail: String) -> String {
        guard let last = head.last, let first = tail.first,
              !last.isWhitespace, !first.isWhitespace
        else { return head + tail }
        return head + " " + tail
    }
}
