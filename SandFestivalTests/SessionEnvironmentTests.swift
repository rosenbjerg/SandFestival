import Foundation
import Testing
@testable import SandFestival

@MainActor
@Suite("Session.composeEnvironment")
struct SessionEnvironmentTests {

    @Test("inherits parent PATH when neither project nor extra override it")
    func inheritsParentPATH() {
        let result = Session.composeEnvironment(
            inherited: ["PATH=/usr/bin:/bin", "HOME=/Users/test"],
            projectEnv: [:],
            extra: [:]
        )
        #expect(pathEntry(in: result) == "/usr/bin:/bin")
        #expect(result.contains("HOME=/Users/test"))
    }

    @Test("project PATH overrides inherited PATH")
    func projectPathOverridesInherited() {
        let result = Session.composeEnvironment(
            inherited: ["PATH=/usr/bin"],
            projectEnv: ["PATH": "/opt/custom/bin"],
            extra: [:]
        )
        #expect(pathEntry(in: result) == "/opt/custom/bin")
    }

    @Test("extra PATH overrides both project and inherited")
    func extraPathOverridesProjectAndInherited() {
        let result = Session.composeEnvironment(
            inherited: ["PATH=/usr/bin"],
            projectEnv: ["PATH": "/opt/proj/bin"],
            extra: ["PATH": "/opt/extra/bin"]
        )
        #expect(pathEntry(in: result) == "/opt/extra/bin")
    }

    @Test("falls back to defaults when nothing supplies a PATH")
    func fallsBackToDefaultsWhenNoPATHAvailable() {
        let result = Session.composeEnvironment(
            inherited: ["HOME=/Users/test"],
            projectEnv: [:],
            extra: [:]
        )
        #expect(pathEntry(in: result) == CommandResolver.defaultPathString)
    }

    @Test("falls back to defaults when inherited PATH is empty")
    func fallsBackToDefaultsWhenInheritedPATHIsEmpty() {
        let result = Session.composeEnvironment(
            inherited: ["PATH="],
            projectEnv: [:],
            extra: [:]
        )
        #expect(pathEntry(in: result) == CommandResolver.defaultPathString)
    }

    @Test("exactly one PATH entry survives composition")
    func exactlyOnePathEntry() {
        let result = Session.composeEnvironment(
            inherited: ["PATH=/usr/bin", "PATH=/bin"],
            projectEnv: ["PATH": "/opt/proj/bin"],
            extra: [:]
        )
        let pathEntries = result.filter { $0.hasPrefix("PATH=") }
        #expect(pathEntries.count == 1)
        #expect(pathEntries.first == "PATH=/opt/proj/bin")
    }

    @Test("non-PATH project env is appended")
    func nonPathProjectEnvIsAppended() {
        let result = Session.composeEnvironment(
            inherited: ["PATH=/usr/bin"],
            projectEnv: ["FOO": "bar", "BAZ": "qux"],
            extra: [:]
        )
        #expect(result.contains("FOO=bar"))
        #expect(result.contains("BAZ=qux"))
    }

    @Test("extra entries take precedence over project entries for non-PATH keys")
    func extraOverridesProjectForNonPath() {
        let result = Session.composeEnvironment(
            inherited: [],
            projectEnv: ["FOO": "from-project"],
            extra: ["FOO": "from-extra"]
        )
        let fooEntries = result.filter { $0.hasPrefix("FOO=") }
        #expect(fooEntries == ["FOO=from-extra"])
    }

    private func pathEntry(in entries: [String]) -> String? {
        for entry in entries where entry.hasPrefix("PATH=") {
            return String(entry.dropFirst("PATH=".count))
        }
        return nil
    }
}
