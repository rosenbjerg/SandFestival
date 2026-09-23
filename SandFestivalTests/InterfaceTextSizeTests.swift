import AppKit
import SwiftUI
import Testing
@testable import SandFestival

@MainActor
@Suite("Interface text size")
struct InterfaceTextSizeTests {

    @Test("Default is the unscaled system size")
    func defaultIsUnscaled() {
        #expect(InterfacePreferences(defaults: makeDefaults()).textSize == .medium)
        #expect(InterfaceTextSize.medium.scale == 1)
    }

    @Test("Sizes are ordered small to extra large")
    func scalesAreOrdered() {
        let scales = InterfaceTextSize.allCases.map(\.scale)
        #expect(scales == scales.sorted())
        #expect(Set(scales).count == scales.count)
    }

    @Test("Choice persists to the same UserDefaults suite")
    func choicePersists() {
        let defaults = makeDefaults()
        InterfacePreferences(defaults: defaults).textSize = .large
        #expect(InterfacePreferences(defaults: defaults).textSize == .large)
    }

    @Test("Point sizes scale off the system text style, whole points only")
    func pointSizesScale() {
        let base = NSFont.preferredFont(forTextStyle: .body).pointSize
        #expect(InterfaceFont.pointSize(.body, scale: 1) == base)
        #expect(InterfaceFont.pointSize(.body, scale: InterfaceTextSize.large.scale)
                == (base * InterfaceTextSize.large.scale).rounded())
        #expect(InterfaceFont.pointSize(.body, scale: 0.01) == 1)
    }

    @Test("Scaling keeps a text style's weight")
    func weightSurvivesScaling() {
        #expect(InterfaceFont.weight(.headline) != .regular)
        #expect(InterfaceFont.weight(.body) == .regular)
    }

    private func makeDefaults() -> UserDefaults {
        let suite = UserDefaults(suiteName: "InterfaceTextSizeTests-\(UUID().uuidString)")!
        suite.removePersistentDomain(forName: suite.description)
        return suite
    }
}
