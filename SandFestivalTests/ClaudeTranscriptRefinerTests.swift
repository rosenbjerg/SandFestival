import Testing
@testable import SandFestival

@Suite("ClaudeTranscriptRefiner")
struct ClaudeTranscriptRefinerTests {

    @Test("runs claude inside the sessions' nono wrapper, silenced")
    func sandboxedLikeSessions() {
        let args = ClaudeTranscriptRefiner.arguments(systemPrompt: "SYSTEM", prompt: "PROMPT")
        let (wrapper, agent) = ArgsSplitter.split(args)

        #expect(ClaudeTranscriptRefiner.command == Project.defaultCommand)
        #expect(wrapper == ArgsSplitter.split(Project.defaultArgs).wrapper + ["--silent"])
        #expect(agent.first == "claude")
    }

    @Test("runs Haiku one-shot with no tools, MCP servers, hooks or session history, prompt last")
    func lockedDownArguments() {
        let args = ArgsSplitter.split(
            ClaudeTranscriptRefiner.arguments(systemPrompt: "SYSTEM", prompt: "PROMPT")
        ).agent

        #expect(args.dropFirst().first == "-p")
        #expect(args.last == "PROMPT")
        #expect(value(after: "--model", in: args) == "haiku")
        #expect(value(after: "--tools", in: args) == "")
        #expect(value(after: "--settings", in: args) == #"{"disableAllHooks":true}"#)
        #expect(value(after: "--system-prompt", in: args) == "SYSTEM")
        #expect(args.contains("--strict-mcp-config"))
        #expect(args.contains("--no-session-persistence"))
        #expect(args.contains("--disable-slash-commands"))
        #expect(!args.contains("--bare"))
    }

    @Test("keeps the inherited environment, swaps in the shell PATH and disables CLAUDE.md")
    func environment() {
        let environment = ClaudeTranscriptRefiner.environment(
            inherited: ["HOME": "/Users/me", "PATH": "/usr/bin"],
            shellPath: "/opt/homebrew/bin:/usr/bin"
        )

        #expect(environment["HOME"] == "/Users/me")
        #expect(environment["PATH"] == "/opt/homebrew/bin:/usr/bin")
        #expect(environment["CLAUDE_CODE_DISABLE_CLAUDE_MDS"] == "1")
    }

    @Test("leaves PATH alone when the shell PATH is unknown")
    func environmentWithoutShellPath() {
        let environment = ClaudeTranscriptRefiner.environment(inherited: ["PATH": "/usr/bin"], shellPath: nil)

        #expect(environment["PATH"] == "/usr/bin")
    }

    private func value(after flag: String, in args: [String]) -> String? {
        guard let index = args.firstIndex(of: flag), args.indices.contains(index + 1) else { return nil }
        return args[index + 1]
    }
}
