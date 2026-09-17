import Foundation

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
