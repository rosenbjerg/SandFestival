import SwiftUI

extension KeyboardShortcut {
    static let dictate = KeyboardShortcut("d", modifiers: [.command, .shift])
    static let duplicateProject = KeyboardShortcut("n", modifiers: [.command, .option])
    static let editProject = KeyboardShortcut("e", modifiers: [.command, .option])
    static let openInFinder = KeyboardShortcut("f", modifiers: [.command, .option])
    static let openInTerminal = KeyboardShortcut("x", modifiers: [.command, .option])

    private static let modifierSymbols: [(EventModifiers, String)] = [
        (.control, "⌃"),
        (.option, "⌥"),
        (.shift, "⇧"),
        (.command, "⌘"),
    ]

    var symbols: String {
        let modifierPart = Self.modifierSymbols
            .filter { modifiers.contains($0.0) }
            .map(\.1)
            .joined()
        return modifierPart + String(key.character).uppercased()
    }

    func tooltip(_ title: String) -> String {
        String(format: String(localized: "shortcut.tooltip"), title, symbols)
    }
}
