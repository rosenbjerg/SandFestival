import Foundation

/// Resolves the user's interactive shell `$PATH` so spawned tools see
/// the same binaries the user sees in Terminal. macOS GUI apps inherit
/// launchd's minimal environment (typically `/usr/bin:/bin:/usr/sbin:/sbin`),
/// which is missing everything users add via `.zshrc` / `.zprofile` and
/// version managers like mise, asdf, fnm, or `~/.cargo/bin`. Without this,
/// `nono` runs but the binaries it routes through silently fail to find
/// the tools that work fine from a Terminal-launched `nono`.
///
/// Resolution runs once per app launch in the background. The result is
/// cached and read synchronously from any thread. If resolution hasn't
/// completed yet (or failed), callers get `nil` and should fall back.
enum UserShellPath {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cached: String?
    nonisolated(unsafe) private static var resolutionStarted = false

    /// Returns the resolved shell PATH, or nil if resolution hasn't
    /// completed or failed. Safe from any thread; never blocks.
    nonisolated static func current() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return cached
    }

    /// Starts a one-shot background resolution. No-op on subsequent
    /// calls. Call early in app launch so the value is warm before the
    /// first session start.
    nonisolated static func resolveInBackground() {
        lock.lock()
        if resolutionStarted {
            lock.unlock()
            return
        }
        resolutionStarted = true
        lock.unlock()

        DispatchQueue.global(qos: .userInitiated).async {
            let resolved = resolveBlocking()
            lock.lock()
            cached = resolved
            lock.unlock()
        }
    }

    /// Extracts the PATH value emitted between our marker pair from
    /// arbitrary shell output. Surfacing this as a pure function lets
    /// the parser be covered without spinning up a real shell.
    nonisolated static func extractPath(from output: String, begin: String, end: String) -> String? {
        guard let beginRange = output.range(of: begin),
              let endRange = output.range(of: end, range: beginRange.upperBound..<output.endIndex)
        else { return nil }
        let value = output[beginRange.upperBound..<endRange.lowerBound]
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Picks the shell binary to drive resolution. Trusts `$SHELL` only
    /// when it points at an executable file — otherwise falls back to
    /// `/bin/zsh` (the modern macOS default). Guards against pathological
    /// environments like `SHELL=/usr/bin/env`, `SHELL=`, or a removed
    /// shell binary, where launching would either fail or run the wrong
    /// program. Exposed for testing.
    nonisolated static func resolveShellExecutable(env: [String: String]) -> String {
        let fallback = "/bin/zsh"
        guard let candidate = env["SHELL"], !candidate.isEmpty else { return fallback }
        return FileManager.default.isExecutableFile(atPath: candidate) ? candidate : fallback
    }

    nonisolated private static func resolveBlocking() -> String? {
        let shell = resolveShellExecutable(env: ProcessInfo.processInfo.environment)
        // Fresh markers per resolution so a hardcoded literal in the
        // user's PATH or shell init can't be mistaken for our fence.
        let token = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let begin = "__SF_PATH_BEGIN_\(token)__"
        let end = "__SF_PATH_END_\(token)__"
        // `-il` makes the shell source both login (`.zprofile`) and
        // interactive (`.zshrc`) init files, covering wherever users
        // typically extend PATH. `/usr/bin/printenv PATH` is absolute
        // so it resolves even if the user's init mangles PATH itself.
        // Markers fence the value off from any noise the shell init
        // prints (p10k instant prompt, nvm chatter, etc.).
        let arguments = [
            "-ilc",
            "printf '%s' '\(begin)'; /usr/bin/printenv PATH; printf '%s' '\(end)'",
        ]
        return runShellAndExtractPath(
            executable: URL(fileURLWithPath: shell),
            arguments: arguments,
            begin: begin,
            end: end,
            timeout: 3.0
        )
    }

    /// Runs an arbitrary shell command and extracts the PATH value
    /// between `begin` and `end` from its stdout. Factored out of
    /// `resolveBlocking` so the subprocess behavior (timeout, exit
    /// handling, marker parsing) can be tested with `/bin/sh -c '…'`
    /// scripts instead of relying on the user's real shell.
    nonisolated static func runShellAndExtractPath(
        executable: URL,
        arguments: [String],
        begin: String,
        end: String,
        timeout: TimeInterval
    ) -> String? {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        let stdout = Pipe()
        process.standardOutput = stdout
        // Redirect stderr to /dev/null so a chatty init script can't fill
        // the buffer and stall the shell waiting for someone to read it.
        process.standardError = FileHandle.nullDevice

        // Termination signals a semaphore so we wake immediately on
        // exit instead of polling on a 20 ms quantum. Wait with the
        // deadline; on timeout SIGKILL and wait once more to reap.
        let done = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in done.signal() }

        do {
            try process.run()
        } catch {
            return nil
        }

        if done.wait(timeout: .now() + timeout) == .timedOut {
            kill(process.processIdentifier, SIGKILL)
            done.wait()
            return nil
        }

        guard process.terminationStatus == 0 else { return nil }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return nil }
        return extractPath(from: output, begin: begin, end: end)
    }
}
