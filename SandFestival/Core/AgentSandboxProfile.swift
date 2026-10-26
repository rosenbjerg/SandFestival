import Foundation

enum AgentSandboxProfile {
    static let pasteboardDenyRule = #"(deny mach-lookup (global-name "com.apple.pasteboard.1"))"#

    nonisolated static let defaultDirectory: URL = {
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return support
            .appendingPathComponent("SandFestival", isDirectory: true)
            .appendingPathComponent("nono", isDirectory: true)
    }()

    static func wrapperArgs(profileURL: URL) -> [String] {
        ["--extends", profileURL.path]
    }

    static func install(
        blockingClipboard: Bool,
        in directory: URL = defaultDirectory,
        pasteDirectory: URL = ImagePaste.directory
    ) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: pasteDirectory, withIntermediateDirectories: true)
        let name = blockingClipboard ? "agent-no-clipboard" : "agent"
        let url = directory.appendingPathComponent("\(name).json", isDirectory: false)
        let data = try encode(name: name, blockingClipboard: blockingClipboard, pasteDirectory: pasteDirectory)
        try data.write(to: url, options: .atomic)
        return url
    }

    static func encode(name: String, blockingClipboard: Bool, pasteDirectory: URL) throws -> Data {
        let profile = Profile(
            meta: .init(name: "sand-festival-\(name)"),
            filesystem: .init(read: [pasteDirectory.path]),
            unsafeMacosSeatbeltRules: blockingClipboard ? [pasteboardDenyRule] : []
        )
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(profile)
    }

    private struct Profile: Encodable {
        struct Meta: Encodable { let name: String }
        struct Filesystem: Encodable { let read: [String] }

        let meta: Meta
        let filesystem: Filesystem
        let unsafeMacosSeatbeltRules: [String]
    }
}
