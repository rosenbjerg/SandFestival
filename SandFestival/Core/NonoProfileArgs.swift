import Foundation

enum NonoProfileArgs {
    static func extract(from wrapper: [String]) -> (profile: String?, rest: [String]) {
        guard let flagIndex = wrapper.firstIndex(of: "--profile"),
              wrapper.index(after: flagIndex) < wrapper.endIndex
        else {
            return (nil, wrapper)
        }
        let valueIndex = wrapper.index(after: flagIndex)
        let profile = wrapper[valueIndex]
        var rest = wrapper
        rest.removeSubrange(flagIndex...valueIndex)
        return (profile, rest)
    }

    static func inject(profile: String?, into wrapper: [String]) -> [String] {
        guard let profile, !profile.isEmpty else { return wrapper }
        var result = wrapper
        let insertionIndex: Int = {
            if let runIndex = result.firstIndex(of: "run") {
                return result.index(after: runIndex)
            }
            return result.startIndex
        }()
        result.insert(contentsOf: ["--profile", profile], at: insertionIndex)
        return result
    }
}
