import AppKit

enum TerminalFont {
    static func resolve(family: String, size: CGFloat) -> NSFont {
        guard !family.isEmpty, let font = font(family: family, size: size) else {
            return .monospacedSystemFont(ofSize: size, weight: .medium)
        }
        return font
    }

    nonisolated static func isAvailable(family: String) -> Bool {
        font(family: family, size: 12)?.isFixedPitch == true
    }

    static let monospacedFamilies: [String] = NSFontManager.shared
        .availableFontFamilies
        .filter(isAvailable(family:))

    nonisolated private static func font(family: String, size: CGFloat) -> NSFont? {
        NSFont(descriptor: NSFontDescriptor(fontAttributes: [.family: family]), size: size)
    }
}
