import Foundation

nonisolated struct WorktreeBaseBranchStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func base(for lineageID: UUID) -> String? {
        guard let stored = stored[lineageID.uuidString] else { return nil }
        let trimmed = stored.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    func remember(_ base: String?, for lineageID: UUID) {
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
    private var stored: [String: String] {
        (defaults.dictionary(forKey: Self.key) ?? [:]).compactMapValues { $0 as? String }
    }

    private static let key = "duplicate.baseBranch"
}
