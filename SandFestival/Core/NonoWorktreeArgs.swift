import Foundation

enum NonoWorktreeArgs {
    static func grantingRepoAccess(repoPath: String, in args: [String]) -> [String] {
        guard !repoPath.isEmpty else { return args }
        let split = ArgsSplitter.split(args)
        if hasAllowGrant(for: repoPath, in: split.wrapper) { return args }
        return ArgsSplitter.join(
            wrapper: split.wrapper + ["--allow", repoPath],
            agent: split.agent
        )
    }

    private static func hasAllowGrant(for repoPath: String, in wrapper: [String]) -> Bool {
        guard wrapper.count >= 2 else { return false }
        for index in 0..<(wrapper.count - 1) where wrapper[index] == "--allow" {
            if wrapper[index + 1] == repoPath { return true }
        }
        return false
    }
}
