import Foundation
import Testing
@testable import SandFestival

@MainActor
@Suite("AgentLaunch")
struct AgentLaunchTests {

    @Test("a one-shot launch resolves the command and composes the session environment")
    func oneShotLaunch() throws {
        let manager = SessionManager(store: makeStore())

        let launch = try manager.oneShotAgentLaunch(
            command: "/bin/sh",
            arguments: ["-c", "true"],
            environment: ["EXAMPLE_FLAG": "1"]
        )

        #expect(launch.executable == "/bin/sh")
        #expect(launch.arguments == ["-c", "true"])
        #expect(launch.environmentDictionary["EXAMPLE_FLAG"] == "1")
        #expect(launch.environmentDictionary["PATH"]?.isEmpty == false)
    }

    @Test("an unresolvable command fails")
    func missingCommand() {
        let manager = SessionManager(store: makeStore())

        #expect(throws: AgentLaunch.Failure.commandNotFound("no-such-command-sandfestival")) {
            try manager.oneShotAgentLaunch(command: "no-such-command-sandfestival", arguments: [], environment: [:])
        }
    }

    @Test("environment entries split at the first equals sign, later entries winning")
    func environmentDictionary() {
        let launch = AgentLaunch(executable: "/bin/sh", arguments: [], environment: ["A=1", "B=x=y", "A=2", "MALFORMED"])

        #expect(launch.environmentDictionary == ["A": "2", "B": "x=y"])
    }

    private func makeStore() -> ProjectStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("AgentLaunchTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("projects.json", isDirectory: false)
        return ProjectStore(fileURL: url)
    }
}
