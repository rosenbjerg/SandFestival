import Foundation

struct PortStore {
    let fileURL: URL

    init(fileURL: URL = PortStore.defaultURL) {
        self.fileURL = fileURL
    }

    static var defaultURL: URL {
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return support
            .appendingPathComponent("SandFestival", isDirectory: true)
            .appendingPathComponent("claude-code-port.txt", isDirectory: false)
    }

    func load() -> UInt16? {
        guard let data = try? Data(contentsOf: fileURL),
              let raw = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              let value = UInt16(raw) else {
            return nil
        }
        return value
    }

    func save(_ port: UInt16) throws {
        let dir = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("\(port)".utf8).write(to: fileURL, options: [.atomic])
    }
}
