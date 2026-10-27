import Foundation

nonisolated struct AgentLaunch: Equatable, Sendable {
    enum Failure: LocalizedError, Equatable {
        case commandNotFound(String)

        var errorDescription: String? {
            switch self {
            case .commandNotFound(let command):
                String(format: String(localized: "agent_launch.error.command_not_found"), command)
            }
        }
    }

    let executable: String
    let arguments: [String]
    let environment: [String]

    var environmentDictionary: [String: String] {
        Dictionary(
            environment.compactMap { entry -> (String, String)? in
                guard let separator = entry.firstIndex(of: "=") else { return nil }
                return (String(entry[..<separator]), String(entry[entry.index(after: separator)...]))
            },
            uniquingKeysWith: { _, last in last }
        )
    }
}

typealias AgentLauncher = @MainActor @Sendable (
    _ command: String,
    _ arguments: [String],
    _ environment: [String: String]
) throws -> AgentLaunch
