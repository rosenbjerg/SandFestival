import Foundation

struct Project: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var path: URL
    var agentID: String
    var command: String
    var args: [String]
    var env: [String: String]
    var autoStart: Bool

    init(
        id: UUID = UUID(),
        name: String,
        path: URL,
        agentID: String = Project.defaultAgentID,
        command: String = Project.defaultCommand,
        args: [String] = Project.defaultArgs,
        env: [String: String] = [:],
        autoStart: Bool = false
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.agentID = agentID
        self.command = command
        self.args = args
        self.env = env
        self.autoStart = autoStart
    }
}

// MARK: - Defaults

extension Project {
    static let defaultAgentID = "claude-code"
    static let defaultCommand = "nono"
    static let defaultArgs: [String] = [
        "run",
        "--allow-cwd",
        "--profile", "claude-code",
        "--allow-launch-services",
        "--",
        "claude",
        "--enable-auto-mode",
    ]
}
