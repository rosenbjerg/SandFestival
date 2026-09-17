import Foundation
import Testing
@testable import SandFestival

@MainActor
@Suite("WorktreeStatusStore")
struct WorktreeStatusStoreTests {

    @Test("a sample lands in the cache under its project id")
    func storesSampledResult() async {
        let probe = ProbeSpy(result: .status(GitStatus(branch: "feat", ahead: 2, changedFiles: 1)))
        let store = WorktreeStatusStore(probe: probe.callable)
        let project = makeWorktreeProject()

        await store.refresh(project: project)?.value

        #expect(store.result(for: project.id) == .status(GitStatus(branch: "feat", ahead: 2, changedFiles: 1)))
        #expect(probe.count == 1)
    }

    @Test("a second refresh is dropped while the first is still running")
    func coalescesConcurrentRefreshes() async {
        let probe = ProbeSpy(result: .status(GitStatus(branch: "feat")))
        let store = WorktreeStatusStore(probe: probe.callable)
        let project = makeWorktreeProject()

        let first = store.refresh(project: project)
        let second = store.refresh(project: project)
        #expect(first != nil)
        #expect(second == nil)

        await first?.value
        #expect(probe.count == 1)
        await store.refresh(project: project)?.value
        #expect(probe.count == 2)
    }

    @Test("a project without a worktree is never sampled")
    func skipsNonWorktreeProjects() async {
        let probe = ProbeSpy(result: .status(GitStatus(branch: "main")))
        let store = WorktreeStatusStore(probe: probe.callable)
        let project = Project(name: "Plain", path: URL(fileURLWithPath: "/Users/me/repo"))

        #expect(store.refresh(project: project) == nil)
        #expect(probe.count == 0)
        #expect(store.result(for: project.id) == nil)
    }

    @Test("an unavailable sample is cached, not discarded")
    func cachesUnavailable() async {
        let probe = ProbeSpy(result: .unavailable)
        let store = WorktreeStatusStore(probe: probe.callable)
        let project = makeWorktreeProject()

        await store.refresh(project: project)?.value

        #expect(store.result(for: project.id) == .unavailable)
    }

    @Test("refreshAll reaps projects that no longer exist")
    func refreshAllPrunesRemovedProjects() async {
        let probe = ProbeSpy(result: .status(GitStatus(branch: "feat")))
        let store = WorktreeStatusStore(probe: probe.callable)
        let kept = makeWorktreeProject(name: "Kept")
        let removed = makeWorktreeProject(name: "Removed")

        await store.refresh(project: kept)?.value
        await store.refresh(project: removed)?.value
        #expect(store.result(for: removed.id) != nil)

        store.refreshAll(projects: [kept])
        #expect(store.result(for: removed.id) == nil)
    }

    @Test("the worktree's recorded base branch reaches the probe")
    func forwardsRecordedBaseBranch() async {
        let probe = ProbeSpy(result: .status(GitStatus(branch: "feat")))
        let store = WorktreeStatusStore(probe: probe.callable)
        let based = makeWorktreeProject(name: "Based", baseBranch: "main")
        let unbased = makeWorktreeProject(name: "Unbased")

        await store.refresh(project: based)?.value
        await store.refresh(project: unbased)?.value

        #expect(probe.recordedBases == ["main", nil])
    }

    @Test("forgetting a project discards a sample already in flight")
    func forgetDropsInFlightResult() async {
        let probe = ProbeSpy(result: .status(GitStatus(branch: "feat")))
        let store = WorktreeStatusStore(probe: probe.callable)
        let project = makeWorktreeProject()

        let task = store.refresh(project: project)
        store.forget(id: project.id)
        await task?.value

        #expect(store.result(for: project.id) == nil)
    }

    // MARK: - Helpers

    private func makeWorktreeProject(
        name: String = "Worktree",
        baseBranch: String? = nil
    ) -> Project {
        Project(
            name: name,
            path: URL(fileURLWithPath: "/Users/me/repo/.worktrees/feat"),
            worktreeInfo: WorktreeInfo(
                sourceRepoPath: URL(fileURLWithPath: "/Users/me/repo"),
                branch: "feat",
                baseBranch: baseBranch
            )
        )
    }

    private final class ProbeSpy: @unchecked Sendable {
        private let lock = NSLock()
        private let result: GitStatusResult
        private var calls = 0

        init(result: GitStatusResult) {
            self.result = result
        }

        var count: Int {
            lock.lock()
            defer { lock.unlock() }
            return calls
        }

        var recordedBases: [String?] {
            lock.lock()
            defer { lock.unlock() }
            return bases
        }

        private(set) var bases: [String?] = []

        var callable: @Sendable (URL, String?) -> GitStatusResult {
            { [self] _, base in
                lock.lock()
                calls += 1
                bases.append(base)
                lock.unlock()
                return result
            }
        }
    }
}
