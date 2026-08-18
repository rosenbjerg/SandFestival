import Foundation

/// A single sample of a working tree's git state, as the sidebar reports it.
struct GitStatus: Equatable {
    /// Branch at HEAD, or `nil` when the working tree is detached. Read live
    /// rather than from `WorktreeInfo`, which only records what the branch
    /// was when the worktree was created — an agent that switched branches
    /// mid-session would otherwise go unnoticed.
    var branch: String?
    /// Commits HEAD has that `comparisonRef` doesn't, and vice versa. Both
    /// stay 0 when there's nothing to compare against.
    var ahead: Int = 0
    var behind: Int = 0
    /// Staged, unstaged, unmerged and untracked paths together — "how much
    /// uncommitted work is sitting here", not a breakdown.
    var changedFiles: Int = 0
    /// What `ahead`/`behind` are measured against: the worktree's recorded
    /// base branch when it has one, otherwise its upstream. `nil` means
    /// neither exists and both counts are meaningless rather than zero.
    var comparisonRef: String?

    var isClean: Bool { changedFiles == 0 }
}

/// The outcome of sampling a directory.
enum GitStatusResult: Equatable {
    /// git couldn't report on the directory — it's gone, was pruned, or was
    /// never a working tree. Which of those it is only matters to the caller.
    case unavailable
    case status(GitStatus)
}

extension GitStatus {
    /// Parses `git status --porcelain=v2 --branch` output. Pure, so the whole
    /// grammar is testable without a repo; the subprocess lives in
    /// `GitWorktree.status(at:)`.
    ///
    /// v2 rather than v1 because only v2 carries the `# branch.*` headers that
    /// make ahead/behind available at all.
    static func parse(porcelainV2 output: String) -> GitStatus {
        var status = GitStatus()
        for line in output.split(whereSeparator: \.isNewline) {
            if let value = line.dropPrefix("# branch.head ") {
                // git spells a detached working tree `(detached)`, which is
                // not a branch name anyone should see.
                status.branch = value == "(detached)" ? nil : String(value)
            } else if let value = line.dropPrefix("# branch.upstream ") {
                status.comparisonRef = String(value)
            } else if let value = line.dropPrefix("# branch.ab ") {
                for field in value.split(separator: " ") {
                    if field.hasPrefix("+") {
                        status.ahead = Int(field.dropFirst()) ?? 0
                    } else if field.hasPrefix("-") {
                        status.behind = Int(field.dropFirst()) ?? 0
                    }
                }
            } else if line.isChangedEntry {
                status.changedFiles += 1
            }
        }
        return status
    }
}

private extension Substring {
    func dropPrefix(_ prefix: String) -> Substring? {
        hasPrefix(prefix) ? dropFirst(prefix.count) : nil
    }

    /// The four entry kinds v2 emits for a path that differs from HEAD:
    /// ordinary (`1`), renamed/copied (`2`), unmerged (`u`) and untracked
    /// (`?`). Ignored entries (`!`) only appear under `--ignored`, which we
    /// never pass.
    var isChangedEntry: Bool {
        guard let kind = first, "12u?".contains(kind) else { return false }
        return dropFirst().hasPrefix(" ")
    }
}
