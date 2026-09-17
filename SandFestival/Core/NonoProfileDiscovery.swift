import Foundation

enum NonoProfileDiscovery {
    static let builtInDefault = "claude-code"

    static func availableProfiles() -> [String] {
        if let names = profilesFromCLI(), !names.isEmpty {
            return names
        }
        return profilesFromFilesystem()
    }

    static func availableProfilesAsync() async -> [String] {
        // Detached: waitUntilExit() would otherwise block the main actor
        // during sheet presentation.
        await Task.detached(priority: .userInitiated) {
            availableProfiles()
        }.value
    }

    // MARK: - CLI

    private static func profilesFromCLI() -> [String]? {
        guard let nono = CommandResolver.resolve("nono") else { return nil }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: nono)
        task.arguments = ["profile", "list"]
        let stdout = Pipe()
        task.standardOutput = stdout
        // An unread stderr pipe would deadlock once nono fills it.
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
        } catch {
            return nil
        }
        // Read to EOF before waiting, or a full pipe deadlocks against the child.
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard task.terminationStatus == 0 else { return nil }
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        let parsed = parse(text)
        return parsed.isEmpty ? nil : parsed
    }

    static func parse(_ text: String) -> [String] {
        var seen = Set<String>()
        var names: [String] = []
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = String(raw)
            guard line.hasPrefix("    ") else { continue }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasSuffix(":") { continue }
            guard let token = trimmed.split(separator: " ", maxSplits: 1).first else { continue }
            let name = String(token)
            if seen.insert(name).inserted {
                names.append(name)
            }
        }
        return names
    }

    // MARK: - Filesystem fallback

    private static func profilesFromFilesystem() -> [String] {
        var names: Set<String> = [builtInDefault]
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/nono/profiles", isDirectory: true)
        if let items = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil
        ) {
            for url in items where url.pathExtension == "json" {
                names.insert(url.deletingPathExtension().lastPathComponent)
            }
        }
        return names.sorted()
    }
}
