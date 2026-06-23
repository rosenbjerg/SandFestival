import Foundation

/// Grants a sandboxed nono run access to a git worktree's source repository.
///
/// A linked worktree's `.git` is a gitlink pointing into
/// `<sourceRepo>/.git/worktrees/<name>`, and the shared object database, refs,
/// and config all live under `<sourceRepo>/.git`. The default wrapper only
/// passes `--allow-cwd`, which covers the worktree directory itself — so every
/// in-worktree git command (status, commit, fetch, rebase…) fails with
/// "operation not permitted" because the source repo root is outside the
/// sandbox. Adding `--allow <sourceRepo>` opens the repository root (and with
/// it the `.git` folder, recursively) so git works as usual.
///
/// The pair lands in the nono *wrapper* segment (before the `--` separator) so
/// it reaches nono rather than the agent. Stored as plain tokens in
/// `Project.args`, exactly like `--allow-cwd`, so it stays visible and editable
/// in the project editor.
enum NonoWorktreeArgs {
    /// Returns `args` with an `--allow <repoPath>` pair appended to the wrapper
    /// segment. Idempotent — if that exact grant is already present the input
    /// is returned unchanged, so duplicating a worktree project doesn't stack
    /// redundant grants. A no-op for an empty `repoPath`.
    static func grantingRepoAccess(repoPath: String, in args: [String]) -> [String] {
        guard !repoPath.isEmpty else { return args }
        let split = ArgsSplitter.split(args)
        if hasAllowGrant(for: repoPath, in: split.wrapper) { return args }
        return ArgsSplitter.join(
            wrapper: split.wrapper + ["--allow", repoPath],
            agent: split.agent
        )
    }

    /// True when `wrapper` already contains an `--allow <repoPath>` pair.
    private static func hasAllowGrant(for repoPath: String, in wrapper: [String]) -> Bool {
        guard wrapper.count >= 2 else { return false }
        for index in 0..<(wrapper.count - 1) where wrapper[index] == "--allow" {
            if wrapper[index + 1] == repoPath { return true }
        }
        return false
    }
}
