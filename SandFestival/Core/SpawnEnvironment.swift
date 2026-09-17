import Foundation

struct SpawnEnvironment: Sendable {
    var additions: [String: String]

    static let empty = SpawnEnvironment(additions: [:])
}
