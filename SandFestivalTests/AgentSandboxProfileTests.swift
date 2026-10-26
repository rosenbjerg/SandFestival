import Foundation
import Testing
@testable import SandFestival

@MainActor
@Suite("AgentSandboxProfile")
struct AgentSandboxProfileTests {

    @Test("blocking adds the pasteboard deny rule and grants read on the paste directory")
    func blockingProfile() throws {
        let paste = URL(fileURLWithPath: "/tmp/pastes", isDirectory: true)
        let json = try decode(AgentSandboxProfile.encode(name: "x", blockingClipboard: true, pasteDirectory: paste))

        #expect(json["unsafe_macos_seatbelt_rules"] as? [String] == [AgentSandboxProfile.pasteboardDenyRule])
        let filesystem = try #require(json["filesystem"] as? [String: Any])
        #expect(filesystem["read"] as? [String] == ["/tmp/pastes"])
    }

    @Test("not blocking keeps the paste directory grant but drops the deny rule")
    func openProfile() throws {
        let paste = URL(fileURLWithPath: "/tmp/pastes", isDirectory: true)
        let json = try decode(AgentSandboxProfile.encode(name: "x", blockingClipboard: false, pasteDirectory: paste))

        #expect(json["unsafe_macos_seatbelt_rules"] as? [String] == [])
        let filesystem = try #require(json["filesystem"] as? [String: Any])
        #expect(filesystem["read"] as? [String] == ["/tmp/pastes"])
    }

    @Test("install writes one file per variant and creates the paste directory")
    func installWritesVariants() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("sandbox-profile-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("nono", isDirectory: true)
        let paste = root.appendingPathComponent("pastes", isDirectory: true)

        let blocked = try AgentSandboxProfile.install(blockingClipboard: true, in: directory, pasteDirectory: paste)
        let open = try AgentSandboxProfile.install(blockingClipboard: false, in: directory, pasteDirectory: paste)

        #expect(blocked != open)
        #expect(FileManager.default.fileExists(atPath: paste.path))
        let blockedJSON = try decode(Data(contentsOf: blocked))
        #expect((blockedJSON["unsafe_macos_seatbelt_rules"] as? [String])?.isEmpty == false)
    }

    @Test("the profile reaches nono as an --extends pair")
    func wrapperArgs() {
        let url = URL(fileURLWithPath: "/a/b.json")
        #expect(AgentSandboxProfile.wrapperArgs(profileURL: url) == ["--extends", "/a/b.json"])
    }

    private func decode(_ data: Data) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
