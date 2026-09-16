import Foundation
import Testing
@testable import SandFestival

@Suite("SidebarFilter.visibleIDs")
struct SidebarFilterTests {
    let parent = Project(name: "Sand Festival", path: URL(fileURLWithPath: "/Users/ada/Code/sand-festival"))
    let sibling = Project(name: "Widgets", path: URL(fileURLWithPath: "/Users/ada/Code/widgets"))
    let child: Project
    let projects: [Project]

    init() {
        child = Project(
            name: "Sidebar filter",
            path: URL(fileURLWithPath: "/Users/ada/Code/sand-festival/.worktrees/sidebar-filter"),
            parentProjectID: parent.id
        )
        projects = [parent, child, sibling]
    }

    private func visible(_ query: String, branch: [Project.ID: String] = [:]) -> Set<Project.ID> {
        SidebarFilter.visibleIDs(projects: projects, query: query) { branch[$0] }
    }

    @Test("an empty or whitespace query shows everything")
    func emptyQuery() {
        #expect(visible("") == Set(projects.map(\.id)))
        #expect(visible("   ") == Set(projects.map(\.id)))
    }

    @Test("matches on the name, case-insensitively")
    func nameMatch() {
        #expect(visible("widg") == [sibling.id])
        #expect(visible("WIDGETS") == [sibling.id])
    }

    @Test("matches on the displayed path")
    func pathMatch() {
        #expect(visible("/Code/widgets") == [sibling.id])
    }

    @Test("matches on the live branch when one is supplied")
    func branchMatch() {
        let ids = visible("feature/login", branch: [sibling.id: "feature/login-form"])
        #expect(ids == [sibling.id])
    }

    @Test("a matching child brings its parent along")
    func childRevealsParent() {
        #expect(visible("sidebar") == [parent.id, child.id])
    }

    @Test("a matching parent keeps all its children")
    func parentRevealsChildren() {
        #expect(visible("sand festival") == [parent.id, child.id])
    }

    @Test("no match hides everything")
    func noMatch() {
        #expect(visible("zzz").isEmpty)
    }
}
