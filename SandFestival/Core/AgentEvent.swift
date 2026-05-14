import Foundation

enum AgentEvent: Equatable {
    case started
    case working
    case idle
    case waitingForPermission
    case waitingForInput
    case blockedByAutoMode
    case errored(reason: String)
    case stopped
}
