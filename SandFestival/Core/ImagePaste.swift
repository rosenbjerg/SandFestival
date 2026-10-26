import AppKit
import Foundation

enum ImagePaste {
    enum Trigger {
        case paste
        case controlV
    }

    nonisolated static let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("sand-festival-pastes", isDirectory: true)

    static func shouldPasteImage(trigger: Trigger, hasText: Bool, hasImage: Bool) -> Bool {
        guard hasImage else { return false }
        switch trigger {
        case .paste: return !hasText
        case .controlV: return true
        }
    }

    static func hasText(_ pasteboard: NSPasteboard) -> Bool {
        !(pasteboard.string(forType: .string) ?? "").isEmpty
    }

    static func hasImage(_ pasteboard: NSPasteboard) -> Bool {
        let types = pasteboard.types ?? []
        guard !types.contains(.fileURL) else { return false }
        return types.contains(.png) || types.contains(.tiff)
    }

    static func pngData(from pasteboard: NSPasteboard) -> Data? {
        if let png = pasteboard.data(forType: .png) { return png }
        guard let tiff = pasteboard.data(forType: .tiff) else { return nil }
        return NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
    }

    static func store(_ png: Data, in directory: URL = ImagePaste.directory) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(UUID().uuidString).png", isDirectory: false)
        try png.write(to: url, options: .atomic)
        return url
    }

    static func purge(directory: URL = ImagePaste.directory) {
        try? FileManager.default.removeItem(at: directory)
    }
}
