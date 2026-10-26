import Foundation
import Testing
@testable import SandFestival

@MainActor
@Suite("AgentSandboxProfile")
struct AgentSandboxProfileTests {

    @Test("blocking adds the pasteboard deny rule and grants read on the paste directory")
    func blockingProfile() throws {
        let paste = URL(fileURLWithPath: "/tmp/pastes", isDirectory: true)
        let json = try decode(AgentSandboxProfile.encode(
            name: "x", extending: "claude-code", blockingClipboard: true, pasteDirectory: paste
        ))

        #expect(json["extends"] as? String == "claude-code")
        #expect(json["unsafe_macos_seatbelt_rules"] as? [String] == [AgentSandboxProfile.pasteboardDenyRule])
        let filesystem = try #require(json["filesystem"] as? [String: Any])
        #expect(filesystem["read"] as? [String] == ["/tmp/pastes"])
    }

    @Test("not blocking keeps the paste directory grant but drops the deny rule")
    func openProfile() throws {
        let paste = URL(fileURLWithPath: "/tmp/pastes", isDirectory: true)
        let json = try decode(AgentSandboxProfile.encode(
            name: "x", extending: nil, blockingClipboard: false, pasteDirectory: paste
        ))

        #expect(json["extends"] == nil)
        #expect(json["unsafe_macos_seatbelt_rules"] as? [String] == [])
        let filesystem = try #require(json["filesystem"] as? [String: Any])
        #expect(filesystem["read"] as? [String] == ["/tmp/pastes"])
    }

    @Test("install writes one file per variant and base profile, and creates the paste directory")
    func installWritesVariants() throws {
        try withTemporaryDirectories { directory, paste in
            let blocked = try AgentSandboxProfile.install(
                blockingClipboard: true, extending: "claude-code", in: directory, pasteDirectory: paste
            )
            let open = try AgentSandboxProfile.install(
                blockingClipboard: false, extending: "claude-code", in: directory, pasteDirectory: paste
            )
            let registry = try AgentSandboxProfile.install(
                blockingClipboard: true, extending: "nolabs-ai/claude", in: directory, pasteDirectory: paste
            )

            #expect(Set([blocked, open, registry]).count == 3)
            #expect(registry.deletingLastPathComponent() == directory)
            #expect(FileManager.default.fileExists(atPath: paste.path))
            let blockedJSON = try decode(Data(contentsOf: blocked))
            #expect((blockedJSON["unsafe_macos_seatbelt_rules"] as? [String])?.isEmpty == false)
        }
    }

    @Test("the selected profile is read from every --profile spelling, wrapper side only")
    func selectedProfile() {
        #expect(AgentSandboxProfile.selectedProfile(in: Project.defaultArgs) == "claude-code")
        #expect(AgentSandboxProfile.selectedProfile(in: ["run", "-p", "xcode", "--", "claude"]) == "xcode")
        #expect(AgentSandboxProfile.selectedProfile(in: ["run", "--profile=xcode", "--", "claude"]) == "xcode")
        #expect(AgentSandboxProfile.selectedProfile(in: ["run", "--", "claude", "--profile", "x"]) == nil)
    }

    @Test("the generated profile replaces the selected one in place")
    func replacesSelectedProfile() {
        #expect(AgentSandboxProfile.replacingProfile(in: Project.defaultArgs, with: "/p.json") == [
            "run", "--profile", "/p.json", "--allow-cwd", "--", "claude", "--enable-auto-mode",
        ])
        #expect(AgentSandboxProfile.replacingProfile(in: ["run", "--profile=xcode", "--", "claude"], with: "/p.json") == [
            "run", "--profile=/p.json", "--", "claude",
        ])
    }

    @Test("without a selected profile the generated one is added after run")
    func addsProfileAfterRun() {
        #expect(AgentSandboxProfile.replacingProfile(in: ["run", "--allow-cwd", "--", "claude"], with: "/p.json") == [
            "run", "--profile", "/p.json", "--allow-cwd", "--", "claude",
        ])
        let noRun = ["--", "claude", "run"]
        #expect(AgentSandboxProfile.replacingProfile(in: noRun, with: "/p.json") == noRun)
    }

    @Test("sandboxing points nono at a profile that extends the project's own")
    func sandboxingExtendsSelected() throws {
        try withTemporaryDirectories { directory, paste in
            let args = try AgentSandboxProfile.sandboxing(
                Project.defaultArgs, blockingClipboard: true, in: directory, pasteDirectory: paste
            )

            #expect(!args.contains("--extends"))
            let profile = try #require(AgentSandboxProfile.selectedProfile(in: args))
            #expect(profile.hasPrefix(directory.path))
            let json = try decode(Data(contentsOf: URL(fileURLWithPath: profile)))
            #expect(json["extends"] as? String == "claude-code")
        }
    }

    @Test("a profile given by path fails the launch, since nono can only extend by name")
    func rejectsPathProfile() throws {
        try withTemporaryDirectories { directory, paste in
            #expect(throws: AgentSandboxProfile.Failure.self) {
                try AgentSandboxProfile.sandboxing(
                    ["run", "--profile", "/x/mine.json", "--", "claude"],
                    blockingClipboard: true, in: directory, pasteDirectory: paste
                )
            }
        }
    }

    private func withTemporaryDirectories(_ body: (URL, URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("sandbox-profile-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(
            root.appendingPathComponent("nono", isDirectory: true),
            root.appendingPathComponent("pastes", isDirectory: true)
        )
    }

    private func decode(_ data: Data) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
