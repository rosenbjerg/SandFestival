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
    /// Set when this project was created via "Duplicate…" against a git
    /// worktree. Holds the path of the originating repo so we can offer a
    /// `git worktree remove` from the right cwd when the project is deleted.
    /// `nil` for plain projects (the common case) — synthesized Codable uses
    /// `decodeIfPresent`, so existing projects.json files keep loading.
    var worktreeInfo: WorktreeInfo?

    init(
        id: UUID = UUID(),
        name: String,
        path: URL,
        agentID: String = Project.defaultAgentID,
        command: String = Project.defaultCommand,
        args: [String] = Project.defaultArgs,
        env: [String: String] = [:],
        autoStart: Bool = false,
        worktreeInfo: WorktreeInfo? = nil
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
    }
}

struct WorktreeInfo: Codable, Hashable {
    /// Path of the source repo the worktree was added from. We run
    /// `git worktree remove` with this as cwd because a worktree directory
    /// may have already been deleted by the user, and `git` only manages
    /// worktrees from inside the main repo.
    var sourceRepoPath: URL
    /// The branch created alongside the worktree (passed to `-b`). Stored
    /// so we can show it in the removal confirmation, not for any control
    /// flow — git itself tracks the actual branch state.
    var branch: String
}

// MARK: - Defaults

extension Project {
    static let defaultAgentID = "claude-code"
    static let defaultCommand = "nono"
    static let defaultArgs: [String] = [
        "run",
        "--profile", "claude-code",
        "--allow-cwd",
        "--allow-launch-services",
        "--",
        "claude",
        "--enable-auto-mode",
    ]
}
