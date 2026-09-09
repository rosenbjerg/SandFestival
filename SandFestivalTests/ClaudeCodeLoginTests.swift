import Foundation
import Testing
@testable import SandFestival

@Suite("ClaudeCodeLogin")
struct ClaudeCodeLoginTests {

    @Test("login runs `claude auth login` behind the nono wrapper")
    func runsAuthLogin() {
        let split = ArgsSplitter.split(ClaudeCodeLogin.args)
        #expect(split.agent == ["claude", "auth", "login"])
        #expect(ClaudeCodeLogin.command == "nono")
    }

    @Test("login reuses the session profile so the two can't drift")
    func reusesSessionProfile() {
        let loginWrapper = ArgsSplitter.split(ClaudeCodeLogin.args).wrapper
        let sessionWrapper = ArgsSplitter.split(Project.defaultArgs).wrapper
        #expect(loginWrapper.starts(with: sessionWrapper))
        #expect(loginWrapper.contains("--profile"))
        #expect(loginWrapper.contains("claude-code"))
    }

    @Test("only the login run gets --allow-launch-services")
    func launchServicesIsLoginOnly() {
        #expect(ClaudeCodeLogin.args.contains("--allow-launch-services"))
        #expect(!Project.defaultArgs.contains("--allow-launch-services"))
    }

    @Test("each scratch directory is fresh, empty and unique")
    func scratchDirectoryIsEmptyAndUnique() throws {
        let first = try ClaudeCodeLogin.makeScratchDirectory()
        let second = try ClaudeCodeLogin.makeScratchDirectory()
        defer {
            try? FileManager.default.removeItem(at: first)
            try? FileManager.default.removeItem(at: second)
        }

        #expect(first != second)
        for url in [first, second] {
            var isDirectory: ObjCBool = false
            #expect(FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory))
            #expect(isDirectory.boolValue)
            let contents = try FileManager.default.contentsOfDirectory(atPath: url.path)
            #expect(contents.isEmpty)
        }
    }
}
