import Testing
@testable import SandFestival

@MainActor
@Suite("NonoCommand")
struct NonoCommandTests {

    @Test("bare names, full paths and stray whitespace all count as nono")
    func matches() {
        #expect(NonoCommand.matches("nono"))
        #expect(NonoCommand.matches("/opt/homebrew/bin/nono"))
        #expect(NonoCommand.matches(" nono "))
    }

    @Test("other commands, including look-alikes, don't")
    func rejects() {
        #expect(!NonoCommand.matches("claude"))
        #expect(!NonoCommand.matches("nono-dev"))
        #expect(!NonoCommand.matches("/usr/bin/xnono"))
    }
}
