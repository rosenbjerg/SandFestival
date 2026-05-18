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

    @Test("an unreadable settings.json makes install throw instead of overwriting it")
    func unreadableSettingsThrows() throws {
        let url = temporaryURL()
        try seed(url: url, content: #"{ "theme": "dark" }"#)
        let fileManager = FileManager.default
        // Drop all permissions: the file exists but can't be read. `try?` used
        // to swallow that and treat the file as empty — which then wiped it.
        try fileManager.setAttributes([.posixPermissions: 0], ofItemAtPath: url.path)
        defer { try? fileManager.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path) }

        let manager = SettingsJSONManager(fileURL: url)
        #expect(throws: SettingsJSONManagerError.self) {
            try manager.install(port: 51789)
        }

        // Restore read access and confirm the user's content survived untouched.
        try fileManager.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
        let json = try parsedSettings(at: url)
        #expect(json["theme"] as? String == "dark")
        #expect(json["hooks"] == nil)
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

    // MARK: - Install state detection

    @Test("detectInstallState reports notInstalled when no entries exist")
    func detectStateNotInstalled() throws {
        let manager = SettingsJSONManager(fileURL: temporaryURL())
        #expect(try manager.detectInstallState(port: 51789) == .notInstalled)
    }

    @Test("detectInstallState reports current after a fresh install")
    func detectStateCurrentAfterInstall() throws {
        let url = temporaryURL()
        let manager = SettingsJSONManager(fileURL: url)
        try manager.install(port: 51789)
        #expect(try manager.detectInstallState(port: 51789) == .current)
    }

    @Test("detectInstallState reports outdated when a legacy http entry is present")
    func detectStateOutdatedForLegacyHttpEntry() throws {
        let url = temporaryURL()
        // Seed every event with the old `type: "http"` shape we used to ship.
        var hooks: [String: Any] = [:]
        let legacyEntry: [String: Any] = [
            "type": "http",
            "url": HookEntryFactory.hookURL(port: 51789),
            "headers": ["Authorization": "Bearer $SAND_FESTIVAL_TOKEN"],
            "allowedEnvVars": ["SAND_FESTIVAL_TOKEN"],
        ]
        for event in HookEvent.allCases {
            hooks[event.rawValue] = [["matcher": "", "hooks": [legacyEntry]]]
        }
        try seed(url: url, content: try jsonString(["hooks": hooks]))

        let manager = SettingsJSONManager(fileURL: url)
        #expect(try manager.detectInstallState(port: 51789) == .outdated)
    }

    @Test("detectInstallState reports outdated when port doesn't match")
    func detectStateOutdatedForDifferentPort() throws {
        let url = temporaryURL()
        let manager = SettingsJSONManager(fileURL: url)
        try manager.install(port: 51789)
        #expect(try manager.detectInstallState(port: 51900) == .outdated)
    }

    @Test("install scopes PreToolUse to the AskUserQuestion matcher")
    func installScopesPreToolUseMatcher() throws {
        let url = temporaryURL()
        let manager = SettingsJSONManager(fileURL: url)
        try manager.install(port: 51789)

        let json = try parsedSettings(at: url)
        let hooks = try #require(json["hooks"] as? [String: Any])
        let preGroups = try #require(hooks["PreToolUse"] as? [[String: Any]])
        // Our PreToolUse entry must live in a group whose matcher is the
        // tool name — otherwise we'd fire a curl on every tool call.
        let ourGroup = try #require(preGroups.first { containsOurEntry($0) })
        #expect((ourGroup["matcher"] as? String) == "AskUserQuestion")

        // Every other event we install stays scoped to the empty matcher.
        for event in HookEvent.allCases where event != .preToolUse {
            let groups = try #require(hooks[event.rawValue] as? [[String: Any]])
            let group = try #require(groups.first { containsOurEntry($0) })
            #expect((group["matcher"] as? String) == "")
        }
    }

    @Test("detectInstallState reports outdated when our PreToolUse entry has the wrong matcher")
    func detectStateOutdatedForWrongPreToolUseMatcher() throws {
        let url = temporaryURL()
        let manager = SettingsJSONManager(fileURL: url)
        try manager.install(port: 51789)

        // Tamper the matcher to simulate a previous install where PreToolUse
        // was registered with the empty matcher (would fire on every tool).
        var json = try parsedSettings(at: url)
        var hooks = try #require(json["hooks"] as? [String: Any])
        var preGroups = try #require(hooks["PreToolUse"] as? [[String: Any]])
        var group = try #require(preGroups.first)
        group["matcher"] = ""
        preGroups[0] = group
        hooks["PreToolUse"] = preGroups
        json["hooks"] = hooks
        try Data(JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]))
            .write(to: url)

        #expect(try manager.detectInstallState(port: 51789) == .outdated)
    }

    @Test("install rewrites legacy http entries to the current command form")
    func installMigratesLegacyEntries() throws {
        let url = temporaryURL()
        let legacyEntry: [String: Any] = [
            "type": "http",
            "url": HookEntryFactory.hookURL(port: 51789),
            "headers": ["Authorization": "Bearer $SAND_FESTIVAL_TOKEN"],
            "allowedEnvVars": ["SAND_FESTIVAL_TOKEN"],
        ]
        var hooks: [String: Any] = [:]
        for event in HookEvent.allCases {
            hooks[event.rawValue] = [["matcher": "", "hooks": [legacyEntry]]]
        }
        try seed(url: url, content: try jsonString(["hooks": hooks]))

        let manager = SettingsJSONManager(fileURL: url)
        try manager.install(port: 51789)

        let json = try parsedSettings(at: url)
        let allHooks = try #require(json["hooks"] as? [String: Any])
        for event in HookEvent.allCases {
            let groups = try #require(allHooks[event.rawValue] as? [[String: Any]])
            let entries = groups.flatMap { ($0["hooks"] as? [[String: Any]]) ?? [] }
            // No more legacy http entries
            #expect(!entries.contains { ($0["type"] as? String) == "http" })
            // At least one current command entry referencing our sentinel
            #expect(entries.contains {
                ($0["type"] as? String) == "command"
                    && (($0["command"] as? String)?.contains(HookEntryFactory.sourceSentinel) ?? false)
            })
        }
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

    private func jsonString(_ value: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted])
        return try #require(String(data: data, encoding: .utf8))
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
                    if let url = entry["url"] as? String {
                        urls.insert(url)
                    } else if let command = entry["command"] as? String,
                              let extracted = extractHookURL(from: command) {
                        urls.insert(extracted)
                    }
                }
            }
        }
        return urls
    }

    private func extractHookURL(from command: String) -> String? {
        // Pulls a `http://127.0.0.1:<port>/event?source=sand-festival` token
        // out of the curl command string the factory produces.
        guard let range = command.range(of: #"http://127\.0\.0\.1:\d+/event\?source=sand-festival"#,
                                        options: .regularExpression) else { return nil }
        return String(command[range])
    }
}
