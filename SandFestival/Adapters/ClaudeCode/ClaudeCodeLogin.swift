import Foundation

enum ClaudeCodeLogin {
    static let command = Project.defaultCommand

    // --allow-launch-services belongs here and not in Project.defaultArgs;
    // see CLAUDE.md "Claude Code login" for both directions of that trap.
    static var args: [String] {
        ArgsSplitter.split(Project.defaultArgs).wrapper
            + ["--allow-launch-services", "--", "claude", "auth", "login"]
    }

    static func makeScratchDirectory() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("claude-login-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
