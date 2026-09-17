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
    var worktreeInfo: WorktreeInfo?
    var parentProjectID: UUID?

    init(
        id: UUID = UUID(),
        name: String,
        path: URL,
        agentID: String = Project.defaultAgentID,
        command: String = Project.defaultCommand,
        args: [String] = Project.defaultArgs,
        env: [String: String] = [:],
        autoStart: Bool = false,
        worktreeInfo: WorktreeInfo? = nil,
        parentProjectID: UUID? = nil
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.agentID = agentID
        self.command = command
        self.args = args
        self.env = env
        self.autoStart = autoStart
        self.worktreeInfo = worktreeInfo
        self.parentProjectID = parentProjectID
    }
}

struct WorktreeInfo: Codable, Hashable {
    var sourceRepoPath: URL
    var branch: String
    var baseBranch: String? = nil
}

// MARK: - Defaults

extension Project {
    static let defaultAgentID = "claude-code"
    static let defaultCommand = "nono"
    static let defaultArgs: [String] = [
        "run",
        "--profile", "claude-code",
        "--allow-cwd",
        "--",
        "claude",
        "--enable-auto-mode",
    ]
}

// MARK: - Display

extension Project {
    var displayPath: String { Project.abbreviatingHome(path.path) }

    static func abbreviatingHome(_ path: String, home: String = NSHomeDirectory()) -> String {
        let home = home.hasSuffix("/") ? String(home.dropLast()) : home
        guard !home.isEmpty, home != "/" else { return path }
        if path == home { return "~" }
        guard path.hasPrefix(home + "/") else { return path }
        return "~" + path.dropFirst(home.count)
    }
}
