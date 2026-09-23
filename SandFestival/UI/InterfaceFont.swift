import AppKit
import SwiftUI

enum InterfaceFont {
    static func resolve(_ style: Font.TextStyle, design: Font.Design = .default, scale: CGFloat) -> Font {
        guard scale != 1 else { return .system(style, design: design) }
        return .system(size: pointSize(style, scale: scale), weight: weight(style), design: design)
    }

    static func pointSize(_ style: Font.TextStyle, scale: CGFloat) -> CGFloat {
        max((basePointSize(style) * scale).rounded(), 1)
    }

    static func weight(_ style: Font.TextStyle) -> Font.Weight {
        let traits = NSFont.preferredFont(forTextStyle: nsStyle(style))
            .fontDescriptor
            .object(forKey: .traits) as? [NSFontDescriptor.TraitKey: Any]
        let raw = traits?[.weight] as? CGFloat ?? NSFont.Weight.regular.rawValue
        return weights
            .min { abs($0.0.rawValue - raw) < abs($1.0.rawValue - raw) }?
            .1 ?? .regular
    }

    private static func basePointSize(_ style: Font.TextStyle) -> CGFloat {
        NSFont.preferredFont(forTextStyle: nsStyle(style)).pointSize
    }

    private static let weights: [(NSFont.Weight, Font.Weight)] = [
        (.ultraLight, .ultraLight),
        (.thin, .thin),
        (.light, .light),
        (.regular, .regular),
        (.medium, .medium),
        (.semibold, .semibold),
        (.bold, .bold),
        (.heavy, .heavy),
        (.black, .black),
    ]

    private static func nsStyle(_ style: Font.TextStyle) -> NSFont.TextStyle {
        switch style {
        case .largeTitle: .largeTitle
        case .title: .title1
        case .title2: .title2
        case .title3: .title3
        case .headline: .headline
        case .subheadline: .subheadline
        case .body: .body
        case .callout: .callout
        case .footnote: .footnote
        case .caption: .caption1
        case .caption2: .caption2
        @unknown default: .body
        }
    }
}

extension EnvironmentValues {
    @Entry var interfaceTextScale: CGFloat = 1
}

extension View {
    func interfaceTextScale(_ scale: CGFloat) -> some View {
        environment(\.interfaceTextScale, scale)
            .font(scale == 1 ? nil : InterfaceFont.resolve(.body, scale: scale))
    }

    func interfaceFont(_ style: Font.TextStyle, design: Font.Design = .default) -> some View {
        modifier(InterfaceFontModifier(style: style, design: design))
    }
}

private struct InterfaceFontModifier: ViewModifier {
    let style: Font.TextStyle
    let design: Font.Design
    @Environment(\.interfaceTextScale) private var scale

    func body(content: Content) -> some View {
        content.font(InterfaceFont.resolve(style, design: design, scale: scale))
    }
}
