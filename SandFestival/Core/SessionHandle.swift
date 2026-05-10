import Foundation

/// Identifies a single live session for the adapter. Adapters use this to bind
/// their own session identifiers (e.g. Claude Code's `session_id`) to the
/// app-side project.
struct SessionHandle: Hashable, Sendable {
    let projectID: UUID
    let workingDirectory: URL
}
