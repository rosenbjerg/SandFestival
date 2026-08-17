import Foundation

/// Remembers which branch the user last based a new worktree on, so the
/// duplicate sheet can pre-select it instead of falling back to the source's
/// current HEAD every time. Most repos have one branch you almost always
/// branch from (`main`), and re-picking it on every duplicate is pure toil.
///
/// Keyed by the **lineage** id — `ProjectDuplicateDraft.resolvedParentProjectID`,
/// the top-level ancestor — so a parent project and every worktree duplicated
/// from it share one memory. They're all the same repo, and keying by path
/// would fragment it: duplicating a worktree child passes *that child's* path
/// as the source repo, so its own key would start out empty.
///
/// A stateless facade over UserDefaults — construct one wherever it's needed
/// rather than threading a shared instance through. Members are `nonisolated`
/// (UserDefaults is thread-safe) so callers off the main actor don't have to
/// hop, same as `GitWorktree`.
struct WorktreeBaseBranchStore {
    private let defaults: UserDefaults

    nonisolated init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The remembered base for `lineageID`, or `nil` when the user has never
    /// picked one — or last picked the "Current HEAD" sentinel, which is
    /// stored as the absence of an entry.
    nonisolated func base(for lineageID: UUID) -> String? {
        guard let stored = stored[lineageID.uuidString] else { return nil }
        let trimmed = stored.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Records `base` as the default for `lineageID`. A `nil` (or blank) base
    /// means the user deliberately chose "Current HEAD", which *forgets* the
    /// entry — the memory then reflects the last actual choice rather than the
    /// last non-nil one.
    ///
    /// Entries for deleted projects are left behind. A UUID never recurs, so a
    /// stale key is a few dead bytes that can't be mistaken for a live one.
    nonisolated func remember(_ base: String?, for lineageID: UUID) {
        var map = stored
        let trimmed = base?.trimmingCharacters(in: .whitespaces) ?? ""
        if trimmed.isEmpty {
            map.removeValue(forKey: lineageID.uuidString)
        } else {
            map[lineageID.uuidString] = trimmed
        }
        defaults.set(map, forKey: Self.key)
    }

    /// Non-string values are dropped per-entry rather than failing the whole
    /// cast, so one bad value written by another build can't wipe the rest.
    nonisolated private var stored: [String: String] {
        (defaults.dictionary(forKey: Self.key) ?? [:]).compactMapValues { $0 as? String }
    }

    nonisolated private static let key = "duplicate.baseBranch"
}
