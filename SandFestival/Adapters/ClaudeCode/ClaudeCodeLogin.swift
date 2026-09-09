import Foundation

/// Argv and scratch-directory policy for the interactive `claude auth login`
/// run behind the "Log In to Claude Code…" window.
enum ClaudeCodeLogin {
    static let command = Project.defaultCommand

    /// The same nono wrapper sessions get, plus `--allow-launch-services`,
    /// running `claude auth login`.
    ///
    /// Both additions are load-bearing and neither belongs in
    /// `Project.defaultArgs`:
    ///
    /// - `--allow-launch-services` is nono's direct-LaunchServices bypass. Its
    ///   browser broker does not shim `open(1)` for a plain `nono run`, so
    ///   without the flag the OAuth hop dies with
    ///   `_LSOpenURLsWithCompletionHandler` error -54. Granting it to one
    ///   short user-initiated process is the point of this window; granting it
    ///   to every unattended agent is what we moved away from.
    /// - `--profile claude-code` carries the paired `allow_launch_services:
    ///   true` profile gate (the CLI flag alone hits a closed gate on
    ///   `default`), plus the `$HOME/Library/Keychains` bypass and
    ///   `~/.claude.json` write the credential needs. On `default` the browser
    ///   hop succeeds and the credential then silently fails to persist.
    static var args: [String] {
        ArgsSplitter.split(Project.defaultArgs).wrapper
            + ["--allow-launch-services", "--", "claude", "auth", "login"]
    }

    /// A fresh empty directory to launch from. `--allow-cwd` grants read+write
    /// to the working directory, so an empty throwaway makes that grant worth
    /// nothing — don't point this at the project path or the home directory.
    static func makeScratchDirectory() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("claude-login-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
