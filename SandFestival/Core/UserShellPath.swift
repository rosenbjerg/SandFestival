import Foundation
import os

enum UserShellPath {
    nonisolated private static let log = Logger(subsystem: "app.sandfestival", category: "UserShellPath")
    nonisolated private static let lock = NSLock()
    // A group, not a semaphore: every waiter must wake without consuming a signal.
    nonisolated private static let resolutionGroup = DispatchGroup()
    nonisolated(unsafe) private static var cached: String?
    nonisolated(unsafe) private static var resolutionStarted = false
    nonisolated(unsafe) private static var resolutionFinished = false

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

    nonisolated static func extractPath(from output: String, begin: String, end: String) -> String? {
        guard let beginRange = output.range(of: begin),
              let endRange = output.range(of: end, range: beginRange.upperBound..<output.endIndex)
        else { return nil }
        let value = output[beginRange.upperBound..<endRange.lowerBound]
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    nonisolated static func resolveShellExecutable(env: [String: String]) -> String {
        let fallback = "/bin/zsh"
        guard let candidate = env["SHELL"], !candidate.isEmpty else { return fallback }
        return FileManager.default.isExecutableFile(atPath: candidate) ? candidate : fallback
    }

    nonisolated private static func resolveBlocking() -> String? {
        let shell = resolveShellExecutable(env: ProcessInfo.processInfo.environment)
        let token = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let begin = "__SF_PATH_BEGIN_\(token)__"
        let end = "__SF_PATH_END_\(token)__"
        // -il sources both .zprofile and .zshrc; printenv is absolute in case
        // the init mangles PATH.
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
            // Never log the PATH itself: directory names leak usernames and project paths.
            log.info("resolved PATH from \(shell, privacy: .public) (\(resolved.utf8.count) bytes)")
        }
        return resolved
    }

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
        // A chatty init script would fill an undrained stderr pipe and stall the shell.
        process.standardError = FileHandle.nullDevice

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
            // .private: init output can echo paths and tokens.
            let sample = String(output.prefix(200))
            log.error("marker pair not found in stdout from \(executable.path, privacy: .public); first 200 chars: \(sample, privacy: .private)")
            return nil
        }
        return extracted
    }
}
