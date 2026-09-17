import Foundation
import Observation

@MainActor
@Observable
final class WorktreeStatusStore {
    private(set) var results: [Project.ID: GitStatusResult] = [:]

    @ObservationIgnored private let probe: @Sendable (URL, String?) -> GitStatusResult
    @ObservationIgnored private var inFlight: [Project.ID: Task<Void, Never>] = [:]

    init(
        probe: @escaping @Sendable (URL, String?) -> GitStatusResult = {
            GitWorktree.status(at: $0, base: $1)
        }
    ) {
        self.probe = probe
    }

    func result(for id: Project.ID) -> GitStatusResult? {
        results[id]
    }

    @discardableResult
    func refresh(project: Project) -> Task<Void, Never>? {
        guard project.worktreeInfo != nil else { return nil }
        guard inFlight[project.id] == nil else { return nil }
        let id = project.id
        let path = project.path
        let base = project.worktreeInfo?.baseBranch
        let probe = probe
        let task = Task { [weak self] in
            let result = await Task.detached(priority: .utility) { probe(path, base) }.value
            guard let self else { return }
            // A project forgotten mid-sample must not be resurrected by its result.
            guard self.inFlight.removeValue(forKey: id) != nil else { return }
            self.results[id] = result
        }
        inFlight[id] = task
        return task
    }

    func refreshAll(projects: [Project]) {
        let live = Set(projects.map(\.id))
        for id in Set(results.keys).union(inFlight.keys) where !live.contains(id) {
            forget(id: id)
        }
        for project in projects {
            refresh(project: project)
        }
    }

    func forget(id: Project.ID) {
        inFlight.removeValue(forKey: id)?.cancel()
        results.removeValue(forKey: id)
    }
}
