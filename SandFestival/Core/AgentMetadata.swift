import Foundation

/// Optional, adapter-supplied metadata the core UI can render generically.
struct AgentMetadata: Equatable, Sendable {
    var permissionMode: String?
    var effort: String?
    var extra: [String: String]

    init(permissionMode: String? = nil, effort: String? = nil, extra: [String: String] = [:]) {
        self.permissionMode = permissionMode
        self.effort = effort
        self.extra = extra
    }

    static let empty = AgentMetadata()
}
