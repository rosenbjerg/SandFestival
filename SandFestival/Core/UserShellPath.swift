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

    private static let markerBegin = "__SAND_FESTIVAL_PATH_BEGIN__"
    private static let markerEnd = "__SAND_FESTIVAL_PATH_END__"

    nonisolated private static func resolveBlocking() -> String? {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        // `-il` makes the shell source both login (`.zprofile`) and
        // interactive (`.zshrc`) init files, covering wherever users
        // typically extend PATH. `/usr/bin/printenv PATH` is absolute
        // so it resolves even if the user's init mangles PATH itself.
        // Markers fence the value off from any noise the shell init
        // prints (p10k instant prompt, nvm chatter, etc.).
        process.arguments = [
            "-ilc",
            "printf '%s' '\(markerBegin)'; /usr/bin/printenv PATH; printf '%s' '\(markerEnd)'",
        ]
        process.standardInput = FileHandle.nullDevice
        let stdout = Pipe()
        process.standardOutput = stdout
        // Redirect stderr to /dev/null so a chatty init script can't fill
        // the buffer and stall the shell waiting for someone to read it.
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return nil
        }

        // 3s ceiling — a healthy shell init returns in tens of ms;
        // anything slower is a misconfigured rc file we don't want to
        // wait on. Poll Process.isRunning rather than blocking on
        // waitUntilExit so we can bail out with SIGKILL.
        let deadline = Date().addingTimeInterval(3.0)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
            process.waitUntilExit()
            return nil
        }

        guard process.terminationStatus == 0 else { return nil }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return nil }
        return extractPath(from: output, begin: markerBegin, end: markerEnd)
    }
}
