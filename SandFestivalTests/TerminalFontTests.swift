import AppKit
import Testing
@testable import SandFestival

@MainActor
@Suite("TerminalFont")
struct TerminalFontTests {

    @Test("An empty family resolves to the system monospaced font")
    func emptyFamilyFallsBackToSystem() {
        let font = TerminalFont.resolve(family: "", size: 15)
        #expect(font == NSFont.monospacedSystemFont(ofSize: 15, weight: .medium))
    }

    @Test("An uninstalled family falls back instead of resolving to a proportional font")
    func unknownFamilyFallsBackToSystem() {
        let font = TerminalFont.resolve(family: "NotAnInstalledFamilyXYZ", size: 13)
        #expect(font == NSFont.monospacedSystemFont(ofSize: 13, weight: .medium))
    }

    @Test("An installed family resolves at the requested size")
    func installedFamilyResolves() {
        let font = TerminalFont.resolve(family: "Menlo", size: 17)
        #expect(font.familyName == "Menlo")
        #expect(font.pointSize == 17)
    }

    @Test("Only fixed-pitch families are offered")
    func familyListIsMonospacedOnly() {
        #expect(TerminalFont.monospacedFamilies.contains("Menlo"))
        #expect(!TerminalFont.monospacedFamilies.contains("Helvetica"))
        #expect(TerminalFont.monospacedFamilies.allSatisfy(TerminalFont.isAvailable(family:)))
    }
}
