import Foundation
import Observation

/// Caches the git state of each worktree-backed project for the sidebar.
///
/// Deliberately not part of `SessionManager`: that owns process lifecycle,
/// persistence and terminal preferences, and none of it has anything to say
/// about git. Keeping the sampling here also means the whole thing tests
/// against an injected probe instead of a real repo.
///
/// The store has no timer of its own. Sampling is driven from outside —
/// primarily by a session leaving `.working`, which is the moment the working
/// tree is most likely to have changed, with the view layer adding a slow
/// backstop for whatever is on screen.
@MainActor
@Observable
final class WorktreeStatusStore {
    private(set) var results: [Project.ID: GitStatusResult] = [:]

    /// Runs off the main actor, so it must not capture anything isolated.
    /// Takes the worktree's recorded base branch alongside its path.
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

    /// Samples `project` unless a sample is already in flight for it — git
    /// status on a large repo isn't instant, and a burst of state transitions
    /// would otherwise pile up subprocesses against the same directory.
    ///
    /// The returned task completes once the result has landed; production
    /// callers ignore it.
    ///
    /// Only worktree-backed projects are sampled: they're the only rows that
    /// display git state, and every sample costs a subprocess.
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
            // `forget` drops the in-flight entry, so a project removed while
            // its sample was running doesn't get resurrected here.
            guard self.inFlight.removeValue(forKey: id) != nil else { return }
            self.results[id] = result
        }
        inFlight[id] = task
        return task
    }

    /// Resamples everything and drops what's cached for projects that no
    /// longer exist — removals never reach the store directly, so this is
    /// where they're reaped.
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
