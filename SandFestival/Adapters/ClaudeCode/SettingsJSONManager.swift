import Foundation

struct SettingsDiffPreview: Equatable {
    let before: String
    let after: String
}

enum SettingsJSONManagerError: Error, Equatable {
    case malformedJSON
    case writeFailed(String)
}

/// Merges/removes Sand Festival hook entries in `~/.claude/settings.json`
/// without disturbing any other settings the user has added. All writes go
/// through a tempfile + fsync + rename so a crash mid-write can't damage
/// the user's existing config.
struct SettingsJSONManager {
    let fileURL: URL

    init(fileURL: URL = SettingsJSONManager.defaultURL) {
        self.fileURL = fileURL
    }

    static var defaultURL: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent("settings.json", isDirectory: false)
    }

    // MARK: - Public API

    func isInstalled(port: UInt16) throws -> Bool {
        let settings = try readSettings()
        let target = HookEntryFactory.hookURL(port: port)
        return ourEntryURLs(in: settings).contains(target)
    }

    func install(port: UInt16, events: [HookEvent] = HookEvent.allCases) throws {
        var settings = try readSettings()
        removeOurEntries(in: &settings)
        addOurEntries(in: &settings, events: events, entry: HookEntryFactory.entry(port: port))
        try writeAtomic(settings)
    }

    func uninstall() throws {
        var settings = try readSettings()
        removeOurEntries(in: &settings)
        try writeAtomic(settings)
    }

    func previewInstall(port: UInt16, events: [HookEvent] = HookEvent.allCases) throws -> SettingsDiffPreview {
        let current = try readSettings()
        var proposed = current
        removeOurEntries(in: &proposed)
        addOurEntries(in: &proposed, events: events, entry: HookEntryFactory.entry(port: port))
        return SettingsDiffPreview(before: prettyPrint(current), after: prettyPrint(proposed))
    }

    // MARK: - Reading

    private func readSettings() throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [:] }
        let data = (try? Data(contentsOf: fileURL)) ?? Data()
        if data.isEmpty { return [:] }
        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw SettingsJSONManagerError.malformedJSON
            }
            return json
        } catch is SettingsJSONManagerError {
            throw SettingsJSONManagerError.malformedJSON
        } catch {
            throw SettingsJSONManagerError.malformedJSON
        }
    }

    // MARK: - Mutation helpers

    private func removeOurEntries(in settings: inout [String: Any]) {
        guard var hooks = settings["hooks"] as? [String: Any] else { return }
        for (event, groupsAny) in hooks {
            guard let groups = groupsAny as? [[String: Any]] else { continue }
            let cleaned = groups.compactMap { group -> [String: Any]? in
                var copy = group
                if let hookList = copy["hooks"] as? [[String: Any]] {
                    let filtered = hookList.filter { !HookEntryFactory.isOurEntry($0) }
                    if filtered.isEmpty { return nil }
                    copy["hooks"] = filtered
                }
                return copy
            }
            if cleaned.isEmpty {
                hooks.removeValue(forKey: event)
            } else {
                hooks[event] = cleaned
            }
        }
        if hooks.isEmpty {
            settings.removeValue(forKey: "hooks")
        } else {
            settings["hooks"] = hooks
        }
    }

    private func addOurEntries(in settings: inout [String: Any], events: [HookEvent], entry: [String: Any]) {
        var hooks = (settings["hooks"] as? [String: Any]) ?? [:]
        for event in events {
            var groups = (hooks[event.rawValue] as? [[String: Any]]) ?? []
            groups.append([
                "matcher": "",
                "hooks": [entry],
            ])
            hooks[event.rawValue] = groups
        }
        settings["hooks"] = hooks
    }

    private func ourEntryURLs(in settings: [String: Any]) -> Set<String> {
        var urls: Set<String> = []
        guard let hooks = settings["hooks"] as? [String: Any] else { return urls }
        for (_, groupsAny) in hooks {
            guard let groups = groupsAny as? [[String: Any]] else { continue }
            for group in groups {
                guard let hookList = group["hooks"] as? [[String: Any]] else { continue }
                for entry in hookList where HookEntryFactory.isOurEntry(entry) {
                    if let url = entry["url"] as? String {
                        urls.insert(url)
                    }
                }
            }
        }
        return urls
    }

    // MARK: - Atomic write

    private func writeAtomic(_ settings: [String: Any]) throws {
        let dir = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try JSONSerialization.data(
            withJSONObject: settings,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        let tempPath = dir
            .appendingPathComponent(".sandfestival.tmp.\(UUID().uuidString)")
            .path

        let fd = open(tempPath, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
        guard fd >= 0 else {
            throw SettingsJSONManagerError.writeFailed("open failed (errno \(errno))")
        }

        let bytesWritten: Int = data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return -1 }
            return write(fd, base, raw.count)
        }
        if bytesWritten != data.count {
            close(fd)
            unlink(tempPath)
            throw SettingsJSONManagerError.writeFailed("write failed (errno \(errno))")
        }
        if fsync(fd) != 0 {
            close(fd)
            unlink(tempPath)
            throw SettingsJSONManagerError.writeFailed("fsync failed (errno \(errno))")
        }
        close(fd)
        if rename(tempPath, fileURL.path) != 0 {
            unlink(tempPath)
            throw SettingsJSONManagerError.writeFailed("rename failed (errno \(errno))")
        }
    }

    private func prettyPrint(_ settings: [String: Any]) -> String {
        guard !settings.isEmpty else { return "{}" }
        guard let data = try? JSONSerialization.data(
            withJSONObject: settings,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        ) else {
            return "{}"
        }
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
