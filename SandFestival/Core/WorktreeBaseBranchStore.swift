import Foundation

struct WorktreeBaseBranchStore {
    private let defaults: UserDefaults

    nonisolated init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    nonisolated func base(for lineageID: UUID) -> String? {
        guard let stored = stored[lineageID.uuidString] else { return nil }
        let trimmed = stored.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

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

    // Per-entry, not `as? [String: String]`: one bad value must not wipe the rest.
    nonisolated private var stored: [String: String] {
        (defaults.dictionary(forKey: Self.key) ?? [:]).compactMapValues { $0 as? String }
    }

    nonisolated private static let key = "duplicate.baseBranch"
}
