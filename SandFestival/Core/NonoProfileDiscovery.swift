import Foundation

/// Discovers nono profile names for the project editor's dropdown.
///
/// Strategy:
///   1. Run `nono profile list` and parse the indented profile entries —
///      this picks up built-ins, packs, and user profiles in one shot.
///   2. If nono isn't on PATH or the call fails, fall back to scanning
///      `~/.config/nono/profiles/*.json` and prepending the built-in
///      `claude-code` default so new projects still get a sensible pick.
enum NonoProfileDiscovery {
    static let builtInDefault = "claude-code"

    static func availableProfiles() -> [String] {
        if let names = profilesFromCLI(), !names.isEmpty {
            return names
        }
        return profilesFromFilesystem()
    }

    /// Async wrapper that runs the (subprocess-spawning) discovery off the
    /// main actor. Call sites in SwiftUI views block view construction
    /// otherwise, which makes the project editor sheet feel sluggish.
    static func availableProfilesAsync() async -> [String] {
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
        // We never read stderr; leaving it on an unread Pipe would deadlock if
        // `nono` wrote more than the pipe buffer holds. Discard it instead.
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
        } catch {
            return nil
        }
        // Read stdout to EOF *before* waiting: reading can't deadlock (the
        // child keeps draining into us), but waiting first while the pipe
        // fills would.
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard task.terminationStatus == 0 else { return nil }
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        let parsed = parse(text)
        return parsed.isEmpty ? nil : parsed
    }

    /// Parses the human-readable `nono profile list` output. Entries look
    /// like a 4-space indent followed by `<name> <description>`; section
    /// headers (`  Built-in:`) are 2-space indent and end with `:`.
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
