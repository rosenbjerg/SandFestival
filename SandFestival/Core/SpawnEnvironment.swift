import Foundation

/// Spawn-time environment overlays an adapter wants to inject. `additions`
/// are merged onto the parent process's environment by the SessionManager
/// before launching the child.
struct SpawnEnvironment: Sendable {
    var additions: [String: String]

    static let empty = SpawnEnvironment(additions: [:])
}
