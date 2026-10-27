import Foundation
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

    @MainActor
    @Test("asks the launcher for a sandboxed one-shot and returns its output")
    func launchesThroughLauncher() async throws {
        let recorder = LaunchRecorder()
        let refiner = ClaudeTranscriptRefiner { command, arguments, environment in
            recorder.record(command: command, arguments: arguments, environment: environment)
            return AgentLaunch(executable: "/bin/echo", arguments: ["Fix the SwiftTerm view."], environment: [])
        }

        let output = try await refiner.refine("fix the swift term view", vocabulary: ["SwiftTerm"])

        #expect(output.trimmingCharacters(in: .whitespacesAndNewlines) == "Fix the SwiftTerm view.")
        let call = try #require(recorder.call)
        #expect(call.command == ClaudeTranscriptRefiner.command)
        #expect(call.arguments.last == "<vocabulary>SwiftTerm</vocabulary>\n<transcript>fix the swift term view</transcript>")
        #expect(call.environment == ["CLAUDE_CODE_DISABLE_CLAUDE_MDS": "1"])
    }

    @Test("a failing launch surfaces as an error")
    func launchFailurePropagates() async {
        let refiner = ClaudeTranscriptRefiner { command, _, _ in
            throw AgentLaunch.Failure.commandNotFound(command)
        }

        await #expect(throws: AgentLaunch.Failure.self) {
            try await refiner.refine("hello", vocabulary: [])
        }
    }

    @MainActor
    @Test("the Claude Code adapter offers Haiku as the agent's clean-up model")
    func adapterOffersRefiner() {
        let refinement = ClaudeCodeAdapter().transcriptRefinement
        let refiner = refinement?.makeRefiner { _, _, _ in
            AgentLaunch(executable: "/bin/echo", arguments: [], environment: [])
        }

        #expect(refinement?.name.isEmpty == false)
        #expect(refiner is ClaudeTranscriptRefiner)
    }

    private func value(after flag: String, in args: [String]) -> String? {
        guard let index = args.firstIndex(of: flag), args.indices.contains(index + 1) else { return nil }
        return args[index + 1]
    }
}

@MainActor
private final class LaunchRecorder: Sendable {
    struct Call {
        let command: String
        let arguments: [String]
        let environment: [String: String]
    }

    private(set) var call: Call?

    func record(command: String, arguments: [String], environment: [String: String]) {
        call = Call(command: command, arguments: arguments, environment: environment)
    }
}
