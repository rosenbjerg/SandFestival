import Foundation

enum SidebarFilter {
    /// Projects the sidebar should show for `query`. A parent survives when
    /// it or any of its children matches; a child survives when it matches
    /// or its parent did, so a hit is never orphaned from the row it nests
    /// under. `branch` supplies the live worktree branch, which is what the
    /// row displays in place of the path — so it's what people type.
    static func visibleIDs(
        projects: [Project],
        query: String,
        branch: (Project.ID) -> String?
    ) -> Set<Project.ID> {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return Set(projects.map(\.id)) }

        let matching = Set(projects.filter { matches($0, needle: needle, branch: branch($0.id)) }.map(\.id))
        var visible = matching
        for project in projects {
            guard let parentID = project.parentProjectID else { continue }
            if matching.contains(project.id) {
                visible.insert(parentID)
            } else if matching.contains(parentID) {
                visible.insert(project.id)
            }
        }
        return visible
    }

    private static func matches(_ project: Project, needle: String, branch: String?) -> Bool {
        if project.name.lowercased().contains(needle) { return true }
        if project.displayPath.lowercased().contains(needle) { return true }
        if let branch, branch.lowercased().contains(needle) { return true }
        return false
    }
}
