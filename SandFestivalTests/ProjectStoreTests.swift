import Foundation
import Testing
@testable import SandFestival

@Suite("ProjectStore")
struct ProjectStoreTests {

    @Test("load returns empty when projects.json is missing")
    func loadReturnsEmptyWhenFileMissing() throws {
        let store = ProjectStore(fileURL: temporaryURL())
        #expect(try store.load().isEmpty)
    }

    @Test("save then load round-trips every field")
    func roundTripsProjectsThroughDisk() throws {
        let url = temporaryURL()
        let store = ProjectStore(fileURL: url)
        let originals = [
            Project(
                name: "Alpha",
                path: URL(fileURLWithPath: "/tmp/alpha"),
                env: ["PATH": "/usr/bin:/bin", "CUSTOM": "value"],
                autoStart: true
            ),
            Project(
                name: "Beta",
                path: URL(fileURLWithPath: "/tmp/beta"),
                command: "claude",
                args: ["--version"]
            ),
        ]

        try store.save(originals)
        let loaded = try store.load()

        #expect(loaded == originals)
    }

    @Test("save creates the parent directory if it doesn't exist")
    func saveCreatesParentDirectory() throws {
        let nested = temporaryURL().deletingLastPathComponent()
            .appendingPathComponent("does/not/exist", isDirectory: true)
            .appendingPathComponent("projects.json", isDirectory: false)
        let store = ProjectStore(fileURL: nested)

        try store.save([Project(name: "Solo", path: URL(fileURLWithPath: "/tmp"))])

        #expect(FileManager.default.fileExists(atPath: nested.path))
    }

    @Test("load throws on malformed JSON instead of returning empty")
    func loadThrowsOnMalformedJSON() throws {
        let url = temporaryURL()
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("not json".utf8).write(to: url)
        let store = ProjectStore(fileURL: url)

        #expect(throws: (any Error).self) {
            _ = try store.load()
        }
    }

    @Test("a default Project carries the nono+claude argv")
    func defaultProjectCarriesNonoArgv() {
        let project = Project(name: "Demo", path: URL(fileURLWithPath: "/tmp"))
        #expect(project.command == "nono")
        #expect(project.args == [
            "run",
            "--allow-cwd",
            "--profile", "claude-code",
            "--allow-launch-services",
            "--",
            "claude",
            "--enable-auto-mode",
        ])
        #expect(project.agentID == "claude-code")
        #expect(project.autoStart == false)
    }

    @Test("saved JSON is human-readable (pretty-printed, sorted keys)")
    func savedJSONIsHumanReadable() throws {
        let url = temporaryURL()
        let store = ProjectStore(fileURL: url)
        try store.save([Project(name: "Demo", path: URL(fileURLWithPath: "/tmp"))])

        let raw = try String(contentsOf: url, encoding: .utf8)
        #expect(raw.contains("\n  "))
        let agentIdx = raw.range(of: "\"agentID\"")
        let nameIdx = raw.range(of: "\"name\"")
        if let agentIdx, let nameIdx {
            #expect(agentIdx.lowerBound < nameIdx.lowerBound)
        }
    }

    // MARK: - Helpers

    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ProjectStoreTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("projects.json", isDirectory: false)
    }
}
