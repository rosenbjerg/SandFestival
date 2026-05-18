import Foundation
import Testing
@testable import SandFestival

@Suite("ProjectEditorTarget identity")
struct ProjectEditorTargetTests {

    @Test("two .add targets with different seed folders have distinct ids")
    func addSeedFoldersAreDistinct() {
        let plain = ProjectEditorTarget.add(seedFolder: nil)
        let seededA = ProjectEditorTarget.add(seedFolder: URL(fileURLWithPath: "/tmp/a"))
        let seededB = ProjectEditorTarget.add(seedFolder: URL(fileURLWithPath: "/tmp/b"))
        // sheet(item:) keys on Identifiable.id — a shared "add" id would make
        // it treat a re-seeded Add target as the same item and drop it.
        #expect(plain.id != seededA.id)
        #expect(seededA.id != seededB.id)
    }

    @Test(".edit targets are identified by the project id and never collide with .add")
    func editTargetUsesProjectID() {
        let project = Project(name: "Demo", path: URL(fileURLWithPath: "/tmp/demo"))
        #expect(ProjectEditorTarget.edit(project).id == project.id.uuidString)
        #expect(ProjectEditorTarget.edit(project).id != ProjectEditorTarget.add(seedFolder: nil).id)
    }
}
