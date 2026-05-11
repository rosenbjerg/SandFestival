import Testing
@testable import SandFestival

@Suite("NonoProfileArgs")
struct NonoProfileArgsTests {

    @Test("extract pulls the profile name and removes both tokens")
    func extractsPair() {
        let wrapper = ["run", "--allow-cwd", "--profile", "claude-code", "--allow-launch-services"]
        let (profile, rest) = NonoProfileArgs.extract(from: wrapper)
        #expect(profile == "claude-code")
        #expect(rest == ["run", "--allow-cwd", "--allow-launch-services"])
    }

    @Test("extract returns nil profile when no --profile flag is present")
    func extractWithoutFlag() {
        let wrapper = ["run", "--allow-cwd", "--allow-launch-services"]
        let (profile, rest) = NonoProfileArgs.extract(from: wrapper)
        #expect(profile == nil)
        #expect(rest == wrapper)
    }

    @Test("extract returns nil when --profile is the last token (no value)")
    func extractDanglingFlag() {
        let wrapper = ["run", "--allow-cwd", "--profile"]
        let (profile, rest) = NonoProfileArgs.extract(from: wrapper)
        #expect(profile == nil)
        #expect(rest == wrapper)
    }

    @Test("inject places --profile <name> immediately after `run`")
    func injectsAfterRun() {
        let wrapper = ["run", "--allow-cwd", "--allow-launch-services"]
        let result = NonoProfileArgs.inject(profile: "xcode", into: wrapper)
        #expect(result == ["run", "--profile", "xcode", "--allow-cwd", "--allow-launch-services"])
    }

    @Test("inject prepends when there is no `run` token")
    func injectWithoutRun() {
        let wrapper = ["--allow-cwd"]
        let result = NonoProfileArgs.inject(profile: "xcode", into: wrapper)
        #expect(result == ["--profile", "xcode", "--allow-cwd"])
    }

    @Test("inject is a no-op when profile is nil or empty")
    func injectNoOp() {
        let wrapper = ["run", "--allow-cwd"]
        #expect(NonoProfileArgs.inject(profile: nil, into: wrapper) == wrapper)
        #expect(NonoProfileArgs.inject(profile: "", into: wrapper) == wrapper)
    }

    @Test("extract then inject round-trips the default wrapper")
    func roundTripsDefaultArgs() {
        let split = ArgsSplitter.split(Project.defaultArgs)
        let (profile, rest) = NonoProfileArgs.extract(from: split.wrapper)
        #expect(profile == "claude-code")
        let rebuilt = NonoProfileArgs.inject(profile: profile, into: rest)
        #expect(rebuilt == split.wrapper)
    }
}
