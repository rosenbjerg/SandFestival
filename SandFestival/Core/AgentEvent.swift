import Foundation

enum AgentEvent: Equatable {
    case started
    case sessionRestarted
    case working
    case idle
    case waitingForPermission
    case waitingForInput
    case blockedByAutoMode
    case errored(reason: String)
    case stopped
    case userInteracted
}
