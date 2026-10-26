import Foundation

enum AgentSandboxProfile {
    static let pasteboardDenyRule = #"(deny mach-lookup (global-name "com.apple.pasteboard.1"))"#

    enum Failure: LocalizedError {
        case profileGivenByPath(String)

        var errorDescription: String? {
            switch self {
            case .profileGivenByPath(let path):
                String(format: String(localized: "session.error.sandbox_profile.path"), path)
            }
        }
    }

    nonisolated static let defaultDirectory: URL = {
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return support
            .appendingPathComponent("SandFestival", isDirectory: true)
            .appendingPathComponent("nono", isDirectory: true)
    }()

    static func sandboxing(
        _ args: [String],
        blockingClipboard: Bool,
        in directory: URL = defaultDirectory,
        pasteDirectory: URL = ImagePaste.directory
    ) throws -> [String] {
        let base = selectedProfile(in: args)
        if let base, looksLikePath(base) {
            throw Failure.profileGivenByPath(base)
        }
        let profile = try install(
            blockingClipboard: blockingClipboard,
            extending: base,
            in: directory,
            pasteDirectory: pasteDirectory
        )
        return replacingProfile(in: args, with: profile.path)
    }

    static func selectedProfile(in args: [String]) -> String? {
        let wrapper = ArgsSplitter.split(args).wrapper
        for (index, arg) in wrapper.enumerated() {
            if arg == "--profile" || arg == "-p" {
                return wrapper.indices.contains(index + 1) ? wrapper[index + 1] : nil
            }
            if arg.hasPrefix("--profile=") {
                return String(arg.dropFirst("--profile=".count))
            }
        }
        return nil
    }

    static func replacingProfile(in args: [String], with path: String) -> [String] {
        let split = ArgsSplitter.split(args)
        var wrapper = split.wrapper
        if let index = wrapper.firstIndex(where: { $0 == "--profile" || $0 == "-p" }),
           wrapper.indices.contains(index + 1) {
            wrapper[index + 1] = path
        } else if let index = wrapper.firstIndex(where: { $0.hasPrefix("--profile=") }) {
            wrapper[index] = "--profile=\(path)"
        } else if let runIndex = wrapper.firstIndex(of: "run") {
            wrapper.insert(contentsOf: ["--profile", path], at: runIndex + 1)
        } else {
            return args
        }
        return args.contains("--") ? ArgsSplitter.join(wrapper: wrapper, agent: split.agent) : wrapper
    }

    static func install(
        blockingClipboard: Bool,
        extending base: String?,
        in directory: URL = defaultDirectory,
        pasteDirectory: URL = ImagePaste.directory
    ) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: pasteDirectory, withIntermediateDirectories: true)
        let name = blockingClipboard ? "agent-no-clipboard" : "agent"
        let fileName = [name, base?.replacingOccurrences(of: "/", with: "+")]
            .compactMap { $0 }
            .joined(separator: "+")
        let url = directory.appendingPathComponent("\(fileName).json", isDirectory: false)
        let data = try encode(
            name: name,
            extending: base,
            blockingClipboard: blockingClipboard,
            pasteDirectory: pasteDirectory
        )
        try data.write(to: url, options: .atomic)
        return url
    }

    static func encode(
        name: String,
        extending base: String?,
        blockingClipboard: Bool,
        pasteDirectory: URL
    ) throws -> Data {
        let profile = Profile(
            meta: .init(name: "sand-festival-\(name)"),
            extends: base,
            filesystem: .init(read: [pasteDirectory.path]),
            unsafeMacosSeatbeltRules: blockingClipboard ? [pasteboardDenyRule] : []
        )
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(profile)
    }

    private static func looksLikePath(_ profile: String) -> Bool {
        profile.hasSuffix(".json") || ["/", ".", "~"].contains { profile.hasPrefix($0) }
    }

    private struct Profile: Encodable {
        struct Meta: Encodable { let name: String }
        struct Filesystem: Encodable { let read: [String] }

        let meta: Meta
        let extends: String?
        let filesystem: Filesystem
        let unsafeMacosSeatbeltRules: [String]
    }
}
