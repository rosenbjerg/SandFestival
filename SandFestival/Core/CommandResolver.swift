import Foundation

enum CommandResolver {
    static let defaultSearchPath: [String] = [
        NSHomeDirectory() + "/.local/bin",
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/usr/bin",
        "/bin",
        "/usr/sbin",
        "/sbin",
    ]

    static var defaultPathString: String {
        defaultSearchPath.joined(separator: ":")
    }

    static func resolve(_ command: String, searchPath: [String] = CommandResolver.defaultSearchPath) -> String? {
        if command.hasPrefix("/") {
            return FileManager.default.isExecutableFile(atPath: command) ? command : nil
        }
        for dir in searchPath {
            let candidate = (dir as NSString).appendingPathComponent(command)
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }
}
