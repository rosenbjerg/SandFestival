import Foundation

struct SessionHandle: Hashable, Sendable {
    let projectID: UUID
    let workingDirectory: URL
}
