import Foundation
import Testing
@testable import SandFestival

@MainActor
@Suite("Session.composeArgs")
struct SessionComposeArgsTests {

    @Test("empty extra args returns the base argv unchanged")
    func emptyExtraReturnsBase() {
        let base = ["run", "--", "claude", "--enable-auto-mode"]
        #expect(Session.composeArgs(base: base, extraAgentArgs: []) == base)
    }

    @Test("extra args land after the agent portion when a -- separator is present")
    func appendsAfterSeparator() {
        let base = ["run", "--profile", "claude-code", "--", "claude", "--enable-auto-mode"]
        let result = Session.composeArgs(base: base, extraAgentArgs: ["--continue"])
        #expect(result == ["run", "--profile", "claude-code", "--", "claude", "--enable-auto-mode", "--continue"])
    }

    @Test("extra args append to the whole argv when there is no -- separator")
    func appendsWhenNoSeparator() {
        let base = ["--enable-auto-mode"]
        let result = Session.composeArgs(base: base, extraAgentArgs: ["--continue"])
        #expect(result == ["--enable-auto-mode", "--continue"])
    }

    @Test("default project args resume with the flag in the agent invocation")
    func defaultArgsContinue() throws {
        let result = Session.composeArgs(base: Project.defaultArgs, extraAgentArgs: ["--continue"])
        // The flag belongs to claude, i.e. after the wrapper's `--` separator.
        let separator = try #require(result.firstIndex(of: "--"))
        #expect(result[separator...].contains("claude"))
        #expect(result.last == "--continue")
    }
}
