import Testing
@testable import SandFestival

@Suite("NonoProfileDiscovery.parse")
struct NonoProfileDiscoveryTests {

    @Test("parses built-in, pack, and user profile names in source order")
    func parsesAllSections() {
        let sample = """
        nono profile: 3 profiles

          Built-in:
            default          Default conservative base profile
            go-dev           Go SDK development profile extends default

          Packs:
            claude-code      Anthropic Claude Code CLI agent

          User (~/.config/nono/profiles/):
            xcode            Claude Code with Xcode grants extends claude-code
        """
        let names = NonoProfileDiscovery.parse(sample)
        #expect(names == ["default", "go-dev", "claude-code", "xcode"])
    }

    @Test("ignores section headers and blank lines")
    func ignoresHeaders() {
        let sample = """
        nono profile: 1 profile

          Built-in:
            default          Default
        """
        #expect(NonoProfileDiscovery.parse(sample) == ["default"])
    }

    @Test("deduplicates repeated names across sections")
    func deduplicates() {
        let sample = """
          Built-in:
            claude-code      Built-in entry
          Packs:
            claude-code      Pack entry
        """
        #expect(NonoProfileDiscovery.parse(sample) == ["claude-code"])
    }

    @Test("returns an empty list when no entries are present")
    func emptyOutput() {
        #expect(NonoProfileDiscovery.parse("").isEmpty)
        #expect(NonoProfileDiscovery.parse("nono profile: 0 profiles\n").isEmpty)
    }
}
