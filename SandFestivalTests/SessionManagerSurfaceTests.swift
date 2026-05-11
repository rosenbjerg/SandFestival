import Foundation
import Testing
@testable import SandFestival

@MainActor
@Suite("SessionManager surface-on-activity")
struct SessionManagerSurfaceTests {

    @Test("activity events on working/waiting/errored count as surface triggers")
    func triggerStatesAreCorrect() {
        #expect(SessionManager.isActivitySurfaceTrigger(.working))
        #expect(SessionManager.isActivitySurfaceTrigger(.waitingForPermission))
        #expect(SessionManager.isActivitySurfaceTrigger(.waitingForIdle))
        #expect(SessionManager.isActivitySurfaceTrigger(.errored(reason: "boom")))
        #expect(!SessionManager.isActivitySurfaceTrigger(.starting))
        #expect(!SessionManager.isActivitySurfaceTrigger(.idle))
        #expect(!SessionManager.isActivitySurfaceTrigger(.blockedByAutoMode))
        #expect(!SessionManager.isActivitySurfaceTrigger(.stopped))
    }

    @Test("a trigger transition moves the session's project to row 0")
    func surfacesOnWorking() throws {
        let (manager, projects) = try makeManager()
        manager.shouldSurfaceOnActivity = { true }

        manager.session(for: projects[1].id)?.apply(event: .working)

        #expect(manager.projects.map(\.id) == [projects[1].id, projects[0].id, projects[2].id])
    }

    @Test("preference off keeps order untouched")
    func ignoredWhenDisabled() throws {
        let (manager, projects) = try makeManager()
        manager.shouldSurfaceOnActivity = { false }

        manager.session(for: projects[1].id)?.apply(event: .working)

        #expect(manager.projects.map(\.id) == projects.map(\.id))
    }

    @Test("non-trigger transitions are ignored even when the preference is on")
    func nonTriggerTransitionsIgnored() throws {
        let (manager, projects) = try makeManager()
        manager.shouldSurfaceOnActivity = { true }

        // .stopped → .idle via .started — not a surface trigger
        manager.session(for: projects[2].id)?.apply(event: .started)

        #expect(manager.projects.map(\.id) == projects.map(\.id))
    }

    @Test("persisted file lags the in-memory move and lands once after the debounce")
    func persistIsDebounced() async throws {
        let (manager, projects, url) = try makeManagerWithURL()
        manager.shouldSurfaceOnActivity = { true }
        manager.persistDebounceDelay = .milliseconds(50)

        manager.session(for: projects[1].id)?.apply(event: .working)
        manager.session(for: projects[2].id)?.apply(event: .working)

        #expect(manager.projects.map(\.id) == [projects[2].id, projects[1].id, projects[0].id])

        let beforeFlush = try ProjectStore(fileURL: url).load()
        #expect(beforeFlush.map(\.id) == projects.map(\.id))

        try await Task.sleep(for: .milliseconds(200))

        let afterFlush = try ProjectStore(fileURL: url).load()
        #expect(afterFlush.map(\.id) == [projects[2].id, projects[1].id, projects[0].id])
    }

    // MARK: - Helpers

    private func makeManager() throws -> (SessionManager, [Project]) {
        let (manager, projects, _) = try makeManagerWithURL()
        return (manager, projects)
    }

    private func makeManagerWithURL() throws -> (SessionManager, [Project], URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SessionManagerSurfaceTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("projects.json", isDirectory: false)
        let store = ProjectStore(fileURL: url)
        let projects = [
            Project(name: "Alpha", path: URL(fileURLWithPath: "/tmp/alpha")),
            Project(name: "Beta", path: URL(fileURLWithPath: "/tmp/beta")),
            Project(name: "Gamma", path: URL(fileURLWithPath: "/tmp/gamma")),
        ]
        try store.save(projects)
        return (SessionManager(store: store), projects, url)
    }
}
