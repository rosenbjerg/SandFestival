import Foundation
import Testing
@testable import SandFestival

@Suite("ProjectDraft path resolution")
struct ProjectEditorDraftTests {

    @Test("resolvedPathString expands a leading tilde to the home directory")
    func resolvesTilde() {
        var draft = ProjectDraft(seedFolder: nil)
        draft.pathString = "~/code/foo"
        #expect(draft.resolvedPathString == NSHomeDirectory() + "/code/foo")
    }

    @Test("resolvedPathString trims surrounding whitespace")
    func trimsWhitespace() {
        var draft = ProjectDraft(seedFolder: nil)
        draft.pathString = "  /tmp/foo  "
        #expect(draft.resolvedPathString == "/tmp/foo")
    }

    @Test("pathIsMissing stays false for an empty field")
    func emptyPathNotFlagged() {
        let draft = ProjectDraft(seedFolder: nil)
        #expect(draft.pathString.isEmpty)
        #expect(draft.pathIsMissing == false)
    }

    @Test("pathIsMissing is true for a path that doesn't exist")
    func missingPathFlagged() {
        var draft = ProjectDraft(seedFolder: nil)
        draft.pathString = "/no/such/directory/sandfestival-\(UUID().uuidString)"
        #expect(draft.pathIsMissing)
    }

    @Test("pathIsMissing is false for an existing directory")
    func existingDirNotFlagged() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        var draft = ProjectDraft(seedFolder: nil)
        draft.pathString = dir.path
        #expect(draft.pathIsMissing == false)
    }

    @Test("isValid follows the tilde-expanded path, not the literal text")
    func isValidUsesExpandedPath() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        // Seeding from a real folder fills name + command + an existing path.
        var draft = ProjectDraft(seedFolder: dir)
        #expect(draft.isValid)
        draft.pathString = "/no/such/dir/\(UUID().uuidString)"
        #expect(draft.isValid == false)
    }

    private func makeTempDir() throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("sandfestival-editor-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
