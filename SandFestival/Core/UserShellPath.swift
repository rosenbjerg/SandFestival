import Foundation
import os

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
    nonisolated private static let log = Logger(subsystem: "app.sandfestival", category: "UserShellPath")
    nonisolated private static let lock = NSLock()
    // DispatchGroup acts as a one-shot latch: `enter()` once when
    // resolution kicks off, `leave()` once when it finishes. Multiple
    // callers can `wait(timeout:)` without consuming signals; after
    // the group is balanced, `wait` returns immediately.
    nonisolated private static let resolutionGroup = DispatchGroup()
    nonisolated(unsafe) private static var cached: String?
    nonisolated(unsafe) private static var resolutionStarted = false
    nonisolated(unsafe) private static var resolutionFinished = false

    /// Returns the resolved shell PATH. If resolution is still in flight
    /// and `timeout > 0`, blocks the calling thread for up to that long
    /// before returning whatever's cached (which may still be nil on
    /// timeout or resolution failure). Safe from any thread.
    ///
    /// The first session start after launch typically hits this before
    /// background resolution has finished — a brief block is worth a
    /// deterministic PATH versus silently falling back to the
    /// launchd-minimal one.
    nonisolated static func current(blockingUpTo timeout: TimeInterval = 0) -> String? {
        lock.lock()
        if resolutionFinished {
            let value = cached
            lock.unlock()
            return value
        }
        let shouldWait = resolutionStarted && timeout > 0
        lock.unlock()

        if shouldWait {
            _ = resolutionGroup.wait(timeout: .now() + timeout)
            lock.lock()
            defer { lock.unlock() }
            return cached
        }
        return nil
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
        resolutionGroup.enter()
        lock.unlock()

        DispatchQueue.global(qos: .userInitiated).async {
            let resolved = resolveBlocking()
            lock.lock()
            cached = resolved
            resolutionFinished = true
            lock.unlock()
            resolutionGroup.leave()
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
        let resolved = runShellAndExtractPath(
            executable: URL(fileURLWithPath: shell),
            arguments: arguments,
            begin: begin,
            end: end,
            timeout: 3.0
        )
        if let resolved {
            // Don't log the PATH itself — directory names can leak
            // usernames and project paths. Byte count is enough to
            // confirm a non-trivial value arrived.
            log.info("resolved PATH from \(shell, privacy: .public) (\(resolved.utf8.count) bytes)")
        }
        return resolved
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
            log.error("failed to launch \(executable.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }

        if done.wait(timeout: .now() + timeout) == .timedOut {
            kill(process.processIdentifier, SIGKILL)
            done.wait()
            log.error("\(executable.path, privacy: .public) exceeded \(timeout)s and was killed")
            return nil
        }

        guard process.terminationStatus == 0 else {
            log.error("\(executable.path, privacy: .public) exited with code \(process.terminationStatus)")
            return nil
        }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else {
            log.error("\(executable.path, privacy: .public) produced non-UTF-8 stdout (\(data.count) bytes)")
            return nil
        }
        guard let extracted = extractPath(from: output, begin: begin, end: end) else {
            // Markers missing or value empty. Sample a short prefix so
            // logs say *why* without dumping the whole init banner —
            // mark private because shell init output can echo paths
            // and tokens.
            let sample = String(output.prefix(200))
            log.error("marker pair not found in stdout from \(executable.path, privacy: .public); first 200 chars: \(sample, privacy: .private)")
            return nil
        }
        return extracted
    }
}
