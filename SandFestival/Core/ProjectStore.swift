import Foundation

struct ProjectStore {
    let fileURL: URL

    init(fileURL: URL = ProjectStore.defaultURL) {
        self.fileURL = fileURL
    }

    func load() throws -> [Project] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        return try decoder.decode([Project].self, from: data)
    }

    func save(_ projects: [Project]) throws {
        let dir = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(projects)

        try data.write(to: fileURL, options: [.atomic])
    }
}

// MARK: - Default location

extension ProjectStore {
    static var defaultURL: URL {
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return support
            .appendingPathComponent("SandFestival", isDirectory: true)
            .appendingPathComponent("projects.json", isDirectory: false)
    }
}
