import Foundation
import Testing
@testable import SandFestival

@Suite("PortStore")
struct PortStoreTests {

    @Test("load returns nil when no port has been persisted")
    func loadReturnsNilForMissingFile() {
        let url = temporaryURL()
        #expect(PortStore(fileURL: url).load() == nil)
    }

    @Test("save then load round-trips the chosen port")
    func saveLoadRoundTrip() throws {
        let url = temporaryURL()
        let store = PortStore(fileURL: url)
        try store.save(51900)
        #expect(store.load() == 51900)
    }

    @Test("save creates the parent directory if it doesn't exist")
    func saveCreatesParentDirectory() throws {
        let nested = temporaryURL().deletingLastPathComponent()
            .appendingPathComponent("nested/dir", isDirectory: true)
            .appendingPathComponent("port.txt", isDirectory: false)
        try PortStore(fileURL: nested).save(51234)
        #expect(FileManager.default.fileExists(atPath: nested.path))
    }

    @Test("load returns nil when file content is not a valid UInt16")
    func loadReturnsNilForGarbage() throws {
        let url = temporaryURL()
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("not-a-port".utf8).write(to: url)
        #expect(PortStore(fileURL: url).load() == nil)
    }

    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("PortStoreTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("port.txt", isDirectory: false)
    }
}
