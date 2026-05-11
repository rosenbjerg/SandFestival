import Foundation

/// Extracts and re-injects the `--profile <name>` pair within nono wrapper
/// args. Used by the project editor to surface the profile as a dropdown
/// while keeping the rest of the wrapper args free-form. The stored
/// `Project.args` array always contains the pair as plain tokens — this
/// helper is purely the UI ↔ argv boundary.
enum NonoProfileArgs {
    /// Removes the first `--profile <name>` pair from `wrapper` and returns
    /// the extracted profile name alongside the remaining tokens. If no
    /// pair is present, returns the input unchanged with `profile == nil`.
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

    /// Inserts `--profile <name>` into `wrapper` at a stable position
    /// (immediately after `run`, falling back to the start). Returns the
    /// input unchanged when `profile` is nil or empty.
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
