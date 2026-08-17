import Foundation
import Testing
@testable import SandFestival

@MainActor
@Suite("WorktreeBaseBranchStore")
struct WorktreeBaseBranchStoreTests {

    @Test("an unremembered lineage has no base")
    func unknownLineageIsNil() {
        let store = WorktreeBaseBranchStore(defaults: makeDefaults())
        #expect(store.base(for: UUID()) == nil)
    }

    @Test("a remembered base survives into a fresh store on the same suite")
    func rememberRoundTrips() {
        let defaults = makeDefaults()
        let lineage = UUID()

        WorktreeBaseBranchStore(defaults: defaults).remember("main", for: lineage)

        #expect(WorktreeBaseBranchStore(defaults: defaults).base(for: lineage) == "main")
    }

    @Test("remembering a new base replaces the old one")
    func rememberOverwrites() {
        let defaults = makeDefaults()
        let store = WorktreeBaseBranchStore(defaults: defaults)
        let lineage = UUID()

        store.remember("main", for: lineage)
        store.remember("develop", for: lineage)

        #expect(store.base(for: lineage) == "develop")
    }

    @Test("each lineage remembers its own base")
    func lineagesAreIndependent() {
        let store = WorktreeBaseBranchStore(defaults: makeDefaults())
        let first = UUID()
        let second = UUID()

        store.remember("main", for: first)
        store.remember("trunk", for: second)

        #expect(store.base(for: first) == "main")
        #expect(store.base(for: second) == "trunk")
    }

    @Test("remembering nil forgets the entry — the user picked Current HEAD")
    func nilForgets() {
        let store = WorktreeBaseBranchStore(defaults: makeDefaults())
        let lineage = UUID()

        store.remember("main", for: lineage)
        store.remember(nil, for: lineage)

        #expect(store.base(for: lineage) == nil)
    }

    @Test("a blank base is treated as nil rather than stored as an empty branch")
    func blankIsForgotten() {
        let store = WorktreeBaseBranchStore(defaults: makeDefaults())
        let lineage = UUID()

        store.remember("main", for: lineage)
        store.remember("   ", for: lineage)

        #expect(store.base(for: lineage) == nil)
    }

    @Test("surrounding whitespace is trimmed on the way in")
    func whitespaceIsTrimmed() {
        let store = WorktreeBaseBranchStore(defaults: makeDefaults())
        let lineage = UUID()

        store.remember("  main  ", for: lineage)

        #expect(store.base(for: lineage) == "main")
    }

    @Test("a non-string stored value is dropped without losing its neighbours")
    func malformedEntriesAreDroppedIndividually() {
        let defaults = makeDefaults()
        let good = UUID()
        let bad = UUID()
        let poisoned: [String: Any] = [good.uuidString: "main", bad.uuidString: 42]
        defaults.set(poisoned, forKey: "duplicate.baseBranch")

        let store = WorktreeBaseBranchStore(defaults: defaults)
        #expect(store.base(for: good) == "main")
        #expect(store.base(for: bad) == nil)

        // And a subsequent write keeps the surviving entry.
        store.remember("develop", for: bad)
        #expect(store.base(for: good) == "main")
        #expect(store.base(for: bad) == "develop")
    }

    // MARK: - Helpers

    private func makeDefaults() -> UserDefaults {
        let name = "app.sandfestival.tests.worktree-base.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}
