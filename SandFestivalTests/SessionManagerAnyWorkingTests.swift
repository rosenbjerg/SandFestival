import Foundation
import Testing
@testable import SandFestival

@MainActor
@Suite("SessionManager anyWorking")
struct SessionManagerAnyWorkingTests {

    @Test("first session entering working fires true; a second one is silent")
    func firesOnceForConcurrentWork() throws {
        let (manager, projects, recorder) = try makeManager()
        let alpha = try #require(manager.session(for: projects[0].id))
        let beta = try #require(manager.session(for: projects[1].id))

        alpha.apply(event: .started)
        beta.apply(event: .started)
        #expect(recorder.values.isEmpty)

        alpha.apply(event: .working)
        beta.apply(event: .working)

        #expect(recorder.values == [true])
    }

    @Test("false fires only when the last working session leaves working")
    func firesFalseWhenAllDone() throws {
        let (manager, projects, recorder) = try makeManager()
        let alpha = try #require(manager.session(for: projects[0].id))
        let beta = try #require(manager.session(for: projects[1].id))
        alpha.apply(event: .started)
        beta.apply(event: .started)
        alpha.apply(event: .working)
        beta.apply(event: .working)

        alpha.apply(event: .idle)
        #expect(recorder.values == [true])

        beta.apply(event: .waitingForPermission)
        #expect(recorder.values == [true, false])
    }

    @Test("a working session dying counts as no longer working")
    func stoppedReleases() throws {
        let (manager, projects, recorder) = try makeManager()
        let alpha = try #require(manager.session(for: projects[0].id))
        alpha.apply(event: .started)
        alpha.apply(event: .working)

        alpha.apply(event: .stopped)

        #expect(recorder.values == [true, false])
    }

    @Test("removing a working project fires false without waiting for a transition")
    func removalReleases() throws {
        let (manager, projects, recorder) = try makeManager()
        let alpha = try #require(manager.session(for: projects[0].id))
        alpha.apply(event: .started)
        alpha.apply(event: .working)

        manager.removeProject(id: projects[0].id)

        #expect(recorder.values == [true, false])
    }

    // MARK: - Helpers

    private final class Recorder {
        var values: [Bool] = []
    }

    private func makeManager() throws -> (SessionManager, [Project], Recorder) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SessionManagerAnyWorkingTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("projects.json", isDirectory: false)
        let store = ProjectStore(fileURL: url)
        let projects = [
            Project(name: "Alpha", path: URL(fileURLWithPath: "/tmp/alpha")),
            Project(name: "Beta", path: URL(fileURLWithPath: "/tmp/beta")),
        ]
        try store.save(projects)
        let manager = SessionManager(store: store)
        let recorder = Recorder()
        manager.anyWorkingDidChange = { recorder.values.append($0) }
        return (manager, projects, recorder)
    }
}
