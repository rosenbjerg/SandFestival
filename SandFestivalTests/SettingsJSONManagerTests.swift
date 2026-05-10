import Foundation
import Testing
@testable import SandFestival

@Suite("SettingsJSONManager")
struct SettingsJSONManagerTests {

    @Test("install creates settings.json with our entries when none existed")
    func installCreatesFreshSettings() throws {
        let url = temporaryURL()
        let manager = SettingsJSONManager(fileURL: url)

        try manager.install(port: 51789)

        let json = try parsedSettings(at: url)
        let hooks = try #require(json["hooks"] as? [String: Any])
        for event in HookEvent.allCases {
            let groups = try #require(hooks[event.rawValue] as? [[String: Any]])
            #expect(groups.contains(where: containsOurEntry))
        }
    }

    @Test("install preserves unrelated top-level fields")
    func installPreservesUnrelatedFields() throws {
        let url = temporaryURL()
        try seed(url: url, content: """
            {
              "theme": "dark",
              "hooks": {
                "SessionStart": [
                  { "matcher": "team", "hooks": [{ "type": "command", "command": "echo hi" }] }
                ]
              }
            }
            """)

        try SettingsJSONManager(fileURL: url).install(port: 51789)

        let json = try parsedSettings(at: url)
        #expect(json["theme"] as? String == "dark")
        let hooks = try #require(json["hooks"] as? [String: Any])
        let sessionStart = try #require(hooks["SessionStart"] as? [[String: Any]])
        // user's original command hook is still there alongside our HTTP one
        let teamGroupExists = sessionStart.contains { group in
            (group["matcher"] as? String) == "team"
        }
        #expect(teamGroupExists)
        #expect(sessionStart.contains(where: containsOurEntry))
    }

    @Test("install is idempotent — running twice yields the same on-disk content")
    func installIsIdempotent() throws {
        let url = temporaryURL()
        let manager = SettingsJSONManager(fileURL: url)

        try manager.install(port: 51789)
        let first = try Data(contentsOf: url)
        try manager.install(port: 51789)
        let second = try Data(contentsOf: url)

        #expect(first == second)
    }

    @Test("install updates the port without leaving stale entries behind")
    func installUpdatesPortIdempotently() throws {
        let url = temporaryURL()
        let manager = SettingsJSONManager(fileURL: url)

        try manager.install(port: 51789)
        try manager.install(port: 51900)

        let json = try parsedSettings(at: url)
        let urls = collectOurURLs(in: json)
        #expect(urls == [HookEntryFactory.hookURL(port: 51900)])
    }

    @Test("uninstall removes only our entries")
    func uninstallRemovesOnlyOurs() throws {
        let url = temporaryURL()
        try seed(url: url, content: """
            {
              "theme": "dark",
              "hooks": {
                "SessionStart": [
                  { "matcher": "team", "hooks": [{ "type": "command", "command": "echo hi" }] }
                ]
              }
            }
            """)

        let manager = SettingsJSONManager(fileURL: url)
        try manager.install(port: 51789)
        try manager.uninstall()

        let json = try parsedSettings(at: url)
        let urls = collectOurURLs(in: json)
        #expect(urls.isEmpty)
        let hooks = try #require(json["hooks"] as? [String: Any])
        let sessionStart = try #require(hooks["SessionStart"] as? [[String: Any]])
        #expect(sessionStart.contains { ($0["matcher"] as? String) == "team" })
    }

    @Test("uninstall on a clean file is a no-op")
    func uninstallOnCleanFileIsNoOp() throws {
        let url = temporaryURL()
        let manager = SettingsJSONManager(fileURL: url)
        try manager.uninstall()
        // No throw, and no file created if there was nothing to write.
        // The file may or may not exist depending on implementation; we just
        // require it doesn't contain our entries.
        if FileManager.default.fileExists(atPath: url.path) {
            let json = try parsedSettings(at: url)
            #expect(collectOurURLs(in: json).isEmpty)
        }
    }

    @Test("isInstalled reflects whether our URL is present")
    func isInstalledReflectsState() throws {
        let url = temporaryURL()
        let manager = SettingsJSONManager(fileURL: url)
        #expect(try !manager.isInstalled(port: 51789))
        try manager.install(port: 51789)
        #expect(try manager.isInstalled(port: 51789))
        #expect(try !manager.isInstalled(port: 51790))  // different port
    }

    @Test("malformed JSON throws SettingsJSONManagerError.malformedJSON")
    func malformedJSONThrows() throws {
        let url = temporaryURL()
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("{this is not json".utf8).write(to: url)
        let manager = SettingsJSONManager(fileURL: url)
        #expect(throws: SettingsJSONManagerError.malformedJSON) {
            _ = try manager.isInstalled(port: 51789)
        }
        #expect(throws: SettingsJSONManagerError.malformedJSON) {
            try manager.install(port: 51789)
        }
    }

    @Test("preview computes before/after without writing to disk")
    func previewDoesNotWriteDisk() throws {
        let url = temporaryURL()
        let manager = SettingsJSONManager(fileURL: url)

        let preview = try manager.previewInstall(port: 51789)

        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(!preview.before.contains(HookEntryFactory.sourceSentinel))
        #expect(preview.after.contains(HookEntryFactory.sourceSentinel))
    }

    // MARK: - Helpers

    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("SettingsJSONManagerTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("settings.json", isDirectory: false)
    }

    private func seed(url: URL, content: String) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(content.utf8).write(to: url)
    }

    private func parsedSettings(at url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func containsOurEntry(_ group: [String: Any]) -> Bool {
        guard let hookList = group["hooks"] as? [[String: Any]] else { return false }
        return hookList.contains(where: HookEntryFactory.isOurEntry)
    }

    private func collectOurURLs(in settings: [String: Any]) -> Set<String> {
        var urls: Set<String> = []
        guard let hooks = settings["hooks"] as? [String: Any] else { return urls }
        for (_, groupsAny) in hooks {
            guard let groups = groupsAny as? [[String: Any]] else { continue }
            for group in groups {
                guard let hookList = group["hooks"] as? [[String: Any]] else { continue }
                for entry in hookList where HookEntryFactory.isOurEntry(entry) {
                    if let url = entry["url"] as? String { urls.insert(url) }
                }
            }
        }
        return urls
    }
}
