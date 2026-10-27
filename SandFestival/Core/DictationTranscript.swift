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

    private static func join(_ head: String, _ tail: String) -> String {
        guard let last = head.last, let first = tail.first,
              !last.isWhitespace, !first.isWhitespace
        else { return head + tail }
        return head + " " + tail
    }
}
