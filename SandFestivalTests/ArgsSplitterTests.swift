import Testing
@testable import SandFestival

@Suite("ArgsSplitter")
struct ArgsSplitterTests {

    @Test("empty args yield empty wrapper and empty agent")
    func splitOfEmpty() {
        let (wrapper, agent) = ArgsSplitter.split([])
        #expect(wrapper.isEmpty)
        #expect(agent.isEmpty)
    }

    @Test("no `--` token: every arg goes into wrapper")
    func splitWithoutSeparator() {
        let (wrapper, agent) = ArgsSplitter.split(["a", "b", "c"])
        #expect(wrapper == ["a", "b", "c"])
        #expect(agent.isEmpty)
    }

    @Test("first bare `--` token splits wrapper from agent")
    func splitWithSeparator() {
        let (wrapper, agent) = ArgsSplitter.split(["nono", "run", "--", "claude", "--enable-auto-mode"])
        #expect(wrapper == ["nono", "run"])
        #expect(agent == ["claude", "--enable-auto-mode"])
    }

    @Test("flags starting with `--` are NOT treated as separators")
    func doubleDashFlagsArentSeparators() {
        let (wrapper, agent) = ArgsSplitter.split(["--profile", "claude-code", "--allow-cwd"])
        #expect(wrapper == ["--profile", "claude-code", "--allow-cwd"])
        #expect(agent.isEmpty)
    }

    @Test("join omits the separator when agent is empty")
    func joinOmitsSeparatorWhenAgentEmpty() {
        #expect(ArgsSplitter.join(wrapper: ["nono"], agent: []) == ["nono"])
        #expect(ArgsSplitter.join(wrapper: [], agent: []).isEmpty)
    }

    @Test("join inserts the separator when agent is non-empty")
    func joinInsertsSeparator() {
        let joined = ArgsSplitter.join(wrapper: ["nono", "run"], agent: ["claude"])
        #expect(joined == ["nono", "run", "--", "claude"])
    }

    @Test("split + join round-trips the SPEC default args")
    func roundTripsDefaultArgs() {
        let split = ArgsSplitter.split(Project.defaultArgs)
        let rejoined = ArgsSplitter.join(wrapper: split.wrapper, agent: split.agent)
        #expect(rejoined == Project.defaultArgs)
    }
}
