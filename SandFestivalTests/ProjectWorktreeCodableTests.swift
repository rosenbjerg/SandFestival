import Foundation
import Testing
@testable import SandFestival

@Suite("Project worktreeInfo Codable")
struct ProjectWorktreeCodableTests {

    @Test("legacy JSON without worktreeInfo decodes with worktreeInfo == nil")
    func legacyJSONDecodesWithoutWorktreeInfo() throws {
        // Mirrors what a pre-duplicate-projects projects.json looks like —
        // the key is simply absent. Synthesised Codable should treat
        // missing optional keys as nil.
        let legacyJSON = """
        [
          {
            "id": "11111111-1111-1111-1111-111111111111",
            "name": "Legacy",
            "path": "file:///tmp/legacy",
            "agentID": "claude-code",
            "command": "nono",
            "args": ["run"],
            "env": {},
            "autoStart": false
          }
        ]
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode([Project].self, from: legacyJSON)
        #expect(decoded.count == 1)
        #expect(decoded[0].name == "Legacy")
        #expect(decoded[0].worktreeInfo == nil)
        #expect(decoded[0].parentProjectID == nil)
    }

    @Test("a Project with worktreeInfo round-trips through JSON")
    func worktreeInfoRoundTrips() throws {
        let original = Project(
            name: "Twin",
            path: URL(fileURLWithPath: "/tmp/twin"),
            worktreeInfo: WorktreeInfo(
                sourceRepoPath: URL(fileURLWithPath: "/tmp/source"),
                branch: "new-feature"
            )
        )

        let encoded = try JSONEncoder().encode([original])
        let decoded = try JSONDecoder().decode([Project].self, from: encoded)

        #expect(decoded == [original])
        #expect(decoded[0].worktreeInfo?.branch == "new-feature")
        #expect(decoded[0].worktreeInfo?.sourceRepoPath.path == "/tmp/source")
    }

    @Test("a Project with parentProjectID round-trips through JSON")
    func parentProjectIDRoundTrips() throws {
        let parentID = UUID()
        let original = Project(
            name: "Child",
            path: URL(fileURLWithPath: "/tmp/child"),
            parentProjectID: parentID
        )

        let encoded = try JSONEncoder().encode([original])
        let decoded = try JSONDecoder().decode([Project].self, from: encoded)

        #expect(decoded == [original])
        #expect(decoded[0].parentProjectID == parentID)
    }
}
