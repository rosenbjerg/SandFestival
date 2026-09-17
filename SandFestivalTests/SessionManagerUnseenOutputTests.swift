import Foundation
import Testing
@testable import SandFestival

@MainActor
@Suite("SessionManager unseen output")
struct SessionManagerUnseenOutputTests {

    @Test("a turn that ends in an unselected session is marked unseen")
    func flaggedWhenNotSelected() throws {
        let (manager, projects) = try makeManager()
        manager.isAppActive = { true }
        let session = try #require(manager.session(for: projects[1].id))

        session.apply(event: .started)
        session.apply(event: .working)
        session.apply(event: .idle)

        #expect(session.hasUnseenOutput)
    }

    @Test("a turn that ends while the user is watching is not marked")
    func notFlaggedWhenViewed() throws {
        let (manager, projects) = try makeManager()
        manager.isAppActive = { true }
        let session = try #require(manager.session(for: projects[0].id))

        session.apply(event: .started)
        session.apply(event: .working)
        session.apply(event: .idle)

        #expect(!session.hasUnseenOutput)
    }

    @Test("the selected session still counts as unseen when the app is in the background")
    func flaggedWhenAppInactive() throws {
        let (manager, projects) = try makeManager()
        manager.isAppActive = { false }
        let session = try #require(manager.session(for: projects[0].id))

        session.apply(event: .started)
        session.apply(event: .working)
        session.apply(event: .idle)

        #expect(session.hasUnseenOutput)
    }

    @Test("settling from starting into idle is not a finished turn")
    func notFlaggedOnLaunchSettle() throws {
        let (manager, projects) = try makeManager()
        manager.isAppActive = { false }
        let session = try #require(manager.session(for: projects[1].id))

        session.apply(event: .started)

        #expect(session.state == .idle)
        #expect(!session.hasUnseenOutput)
    }

    @Test("viewing the session clears the mark")
    func clearedWhenSeen() throws {
        let (manager, projects) = try makeManager()
        manager.isAppActive = { true }
        let session = try #require(manager.session(for: projects[1].id))
        session.apply(event: .started)
        session.apply(event: .working)
        session.apply(event: .idle)
        #expect(session.hasUnseenOutput)

        manager.selectedProjectID = projects[1].id
        manager.markSelectedSessionSeen()

        #expect(!session.hasUnseenOutput)
    }

    @Test("a new turn supersedes the mark")
    func clearedWhenWorkResumes() throws {
        let (manager, projects) = try makeManager()
        manager.isAppActive = { true }
        let session = try #require(manager.session(for: projects[1].id))
        session.apply(event: .started)
        session.apply(event: .working)
        session.apply(event: .idle)
        #expect(session.hasUnseenOutput)

        session.apply(event: .working)

        #expect(!session.hasUnseenOutput)
    }

    @Test("stopping supersedes the mark")
    func clearedWhenStopped() throws {
        let (manager, projects) = try makeManager()
        manager.isAppActive = { true }
        let session = try #require(manager.session(for: projects[1].id))
        session.apply(event: .started)
        session.apply(event: .working)
        session.apply(event: .idle)
        #expect(session.hasUnseenOutput)

        session.apply(event: .stopped)

        #expect(!session.hasUnseenOutput)
    }

    // MARK: - Helpers

    private func makeManager() throws -> (SessionManager, [Project]) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SessionManagerUnseenOutputTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("projects.json", isDirectory: false)
        let store = ProjectStore(fileURL: url)
        let projects = [
            Project(name: "Alpha", path: URL(fileURLWithPath: "/tmp/alpha")),
            Project(name: "Beta", path: URL(fileURLWithPath: "/tmp/beta")),
        ]
        try store.save(projects)
        let manager = SessionManager(store: store)
        #expect(manager.selectedProjectID == projects[0].id)
        return (manager, projects)
    }
}
