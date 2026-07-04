import Foundation
import Testing
@testable import SandFestival

@Suite("ClaudeCodeUpdater.searchPath")
struct ClaudeCodeUpdaterTests {

    @Test("nil shell PATH falls back to the default search path")
    func nilShellPathUsesDefault() {
        #expect(ClaudeCodeUpdater.searchPath(shellPath: nil) == CommandResolver.defaultSearchPath)
    }

    @Test("empty shell PATH falls back to the default search path")
    func emptyShellPathUsesDefault() {
        #expect(ClaudeCodeUpdater.searchPath(shellPath: "") == CommandResolver.defaultSearchPath)
        #expect(ClaudeCodeUpdater.searchPath(shellPath: "::") == CommandResolver.defaultSearchPath)
    }

    @Test("shell PATH dirs come first, then the non-duplicate fallback dirs")
    func shellDirsTakePrecedence() {
        let result = ClaudeCodeUpdater.searchPath(shellPath: "/custom/bin:/opt/tools")
        #expect(result.starts(with: ["/custom/bin", "/opt/tools"]))
        // Fallback dirs are appended so a native ~/.local/bin install still resolves.
        for dir in CommandResolver.defaultSearchPath {
            #expect(result.contains(dir))
        }
    }

    @Test("a fallback dir already present in the shell PATH is not duplicated")
    func noDuplicateFallbackDir() {
        let shared = CommandResolver.defaultSearchPath.first!
        let result = ClaudeCodeUpdater.searchPath(shellPath: "\(shared):/custom/bin")
        #expect(result.filter { $0 == shared }.count == 1)
        #expect(result.first == shared)
    }
}
