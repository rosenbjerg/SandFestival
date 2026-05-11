import Foundation
import Testing
@testable import SandFestival

@MainActor
@Suite("SessionManager.moveProjects")
struct SessionManagerMoveTests {

    @Test("reorders projects and persists the new order")
    func reordersAndPersists() throws {
        let url = temporaryURL()
        let store = ProjectStore(fileURL: url)
        let alpha = Project(name: "Alpha", path: URL(fileURLWithPath: "/tmp/alpha"))
        let beta = Project(name: "Beta", path: URL(fileURLWithPath: "/tmp/beta"))
        let gamma = Project(name: "Gamma", path: URL(fileURLWithPath: "/tmp/gamma"))
        try store.save([alpha, beta, gamma])

        let manager = SessionManager(store: store)
        manager.moveProjects(fromOffsets: IndexSet(integer: 0), toOffset: 3)

        #expect(manager.projects.map(\.name) == ["Beta", "Gamma", "Alpha"])
        let reloaded = try store.load()
        #expect(reloaded.map(\.name) == ["Beta", "Gamma", "Alpha"])
    }

    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("SessionManagerMoveTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("projects.json", isDirectory: false)
    }
}
