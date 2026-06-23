import Testing
@testable import SandFestival

@Suite("NonoWorktreeArgs")
struct NonoWorktreeArgsTests {

    @Test("grants repo access by appending --allow to the wrapper segment")
    func appendsToWrapper() {
        let result = NonoWorktreeArgs.grantingRepoAccess(
            repoPath: "/Users/me/repo",
            in: Project.defaultArgs
        )
        let split = ArgsSplitter.split(result)
        #expect(split.wrapper.suffix(2) == ["--allow", "/Users/me/repo"])
        // The agent segment is untouched.
        #expect(split.agent == ["claude", "--enable-auto-mode"])
    }

    @Test("inserts before the -- separator, not into the agent args")
    func landsBeforeSeparator() {
        let result = NonoWorktreeArgs.grantingRepoAccess(
            repoPath: "/repo",
            in: ["run", "--allow-cwd", "--", "claude"]
        )
        #expect(result == ["run", "--allow-cwd", "--allow", "/repo", "--", "claude"])
    }

    @Test("appends when there is no -- separator")
    func noSeparator() {
        let result = NonoWorktreeArgs.grantingRepoAccess(
            repoPath: "/repo",
            in: ["run", "--allow-cwd"]
        )
        #expect(result == ["run", "--allow-cwd", "--allow", "/repo"])
    }

    @Test("is idempotent for the same repo path")
    func idempotent() {
        let once = NonoWorktreeArgs.grantingRepoAccess(
            repoPath: "/Users/me/repo",
            in: Project.defaultArgs
        )
        let twice = NonoWorktreeArgs.grantingRepoAccess(
            repoPath: "/Users/me/repo",
            in: once
        )
        #expect(twice == once)
    }

    @Test("adds a distinct grant for a different repo path")
    func differentPathStacks() {
        let first = NonoWorktreeArgs.grantingRepoAccess(repoPath: "/repo/a", in: Project.defaultArgs)
        let second = NonoWorktreeArgs.grantingRepoAccess(repoPath: "/repo/b", in: first)
        let split = ArgsSplitter.split(second)
        #expect(split.wrapper.contains("/repo/a"))
        #expect(split.wrapper.contains("/repo/b"))
    }

    @Test("is a no-op for an empty repo path")
    func emptyPathNoOp() {
        let result = NonoWorktreeArgs.grantingRepoAccess(repoPath: "", in: Project.defaultArgs)
        #expect(result == Project.defaultArgs)
    }
}
