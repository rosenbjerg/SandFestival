import Foundation

/// Splits and rejoins argv on the bare `--` separator. The Project model
/// stores a single flat args array; the project editor presents two lists
/// (wrapper / agent), so we round-trip through this helper at the boundary.
enum ArgsSplitter {
    static func split(_ args: [String]) -> (wrapper: [String], agent: [String]) {
        guard let index = args.firstIndex(of: "--") else {
            return (args, [])
        }
        return (
            Array(args.prefix(index)),
            Array(args.suffix(from: args.index(after: index)))
        )
    }

    static func join(wrapper: [String], agent: [String]) -> [String] {
        agent.isEmpty ? wrapper : wrapper + ["--"] + agent
    }
}
