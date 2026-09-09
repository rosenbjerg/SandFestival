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
    /// When this project was created via "Duplicate…", points at the
    /// originating `Project.id`. The sidebar uses it to indent the row
    /// underneath its parent. `nil` for top-level projects (the common
    /// case); synthesized Codable uses `decodeIfPresent`, so legacy
    /// projects.json files keep loading.
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
    /// Path of the source repo the worktree was added from. We run
    /// `git worktree remove` with this as cwd because a worktree directory
    /// may have already been deleted by the user, and `git` only manages
    /// worktrees from inside the main repo.
    var sourceRepoPath: URL
    /// The branch created alongside the worktree (passed to `-b`). Stored
    /// so we can show it in the removal confirmation, not for any control
    /// flow — git itself tracks the actual branch state.
    var branch: String
    /// The branch this worktree was forked from, when one was chosen. The
    /// sidebar measures ahead/behind against it: a branch created with `-b`
    /// has no upstream, so without a recorded base there'd be nothing to
    /// compare it to and the numbers would always read zero — which is the
    /// common case, not an edge one. `nil` for worktrees checked out from an
    /// existing branch (their `--track` upstream serves instead) and for
    /// worktrees recorded before this field existed.
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
