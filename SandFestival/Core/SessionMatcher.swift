import Foundation

/// How an adapter identifies which Project a reported event belongs to. The
/// only adapter in the tree (Claude Code) resolves Claude's `session_id` to
/// a project ID inside its own `SessionBindingStore` before reporting, so the
/// sink only needs to handle the project-ID and working-directory cases here.
enum SessionMatcher: Hashable, Sendable {
    case workingDirectory(URL)
    case projectID(UUID)
}
