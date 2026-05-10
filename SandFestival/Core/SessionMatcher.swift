import Foundation

enum SessionMatcher: Hashable, Sendable {
    case sessionID(String)
    case workingDirectory(URL)
    case projectID(UUID)
    case pid(pid_t)
}
