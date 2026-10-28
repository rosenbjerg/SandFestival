import SwiftUI
import Testing
@testable import SandFestival

@MainActor
@Suite("KeyboardShortcuts")
struct KeyboardShortcutsTests {

    @Test("Modifiers render in the macOS menu order: control, option, shift, command")
    func modifierOrder() {
        let shortcut = KeyboardShortcut("k", modifiers: [.command, .shift, .option, .control])
        #expect(shortcut.symbols == "⌃⌥⇧⌘K")
    }

    @Test("A tooltip appends the shortcut's symbols to the title")
    func tooltipFormat() {
        let shortcut = KeyboardShortcut("n", modifiers: [.command, .option])
        #expect(shortcut.tooltip("Duplicate") == "Duplicate (⌥⌘N)")
    }
}
