import Foundation
import Testing
@testable import SandFestival

@Suite("UserShellPath.extractPath")
struct UserShellPathTests {

    @Test("returns the value enclosed by markers, trimmed")
    func returnsValueBetweenMarkers() {
        let output = "p10k noise\n__B__/usr/local/bin:/usr/bin:/bin\n__E__\n"
        #expect(UserShellPath.extractPath(from: output, begin: "__B__", end: "__E__") == "/usr/local/bin:/usr/bin:/bin")
    }

    @Test("returns nil when the begin marker is absent")
    func returnsNilWithoutBeginMarker() {
        let output = "/usr/bin:/bin__E__"
        #expect(UserShellPath.extractPath(from: output, begin: "__B__", end: "__E__") == nil)
    }

    @Test("returns nil when the end marker is absent")
    func returnsNilWithoutEndMarker() {
        let output = "__B__/usr/bin:/bin"
        #expect(UserShellPath.extractPath(from: output, begin: "__B__", end: "__E__") == nil)
    }

    @Test("returns nil when the enclosed value is empty whitespace")
    func returnsNilForEmptyValue() {
        let output = "__B__   \n__E__"
        #expect(UserShellPath.extractPath(from: output, begin: "__B__", end: "__E__") == nil)
    }

    @Test("only honors the first marker pair, ignoring later occurrences")
    func usesFirstMatch() {
        let output = "__B__/first:/path__E__ then __B__/wrong__E__"
        #expect(UserShellPath.extractPath(from: output, begin: "__B__", end: "__E__") == "/first:/path")
    }

    @Test("ignores a stray end marker that appears before the begin marker")
    func ignoresEarlyEndMarker() {
        let output = "noise __E__ before __B__/the:/real/path__E__"
        #expect(UserShellPath.extractPath(from: output, begin: "__B__", end: "__E__") == "/the:/real/path")
    }
}

@Suite("UserShellPath.resolveShellExecutable")
struct UserShellPathShellPickerTests {

    @Test("returns the SHELL value when it is an executable file")
    func returnsExecutableShell() {
        // /bin/sh is guaranteed to be an executable on every macOS host.
        let picked = UserShellPath.resolveShellExecutable(env: ["SHELL": "/bin/sh"])
        #expect(picked == "/bin/sh")
    }

    @Test("falls back to /bin/zsh when SHELL is unset")
    func fallsBackWhenUnset() {
        let picked = UserShellPath.resolveShellExecutable(env: [:])
        #expect(picked == "/bin/zsh")
    }

    @Test("falls back to /bin/zsh when SHELL is empty")
    func fallsBackWhenEmpty() {
        let picked = UserShellPath.resolveShellExecutable(env: ["SHELL": ""])
        #expect(picked == "/bin/zsh")
    }

    @Test("falls back to /bin/zsh when SHELL is not an executable file")
    func fallsBackWhenNotExecutable() {
        let picked = UserShellPath.resolveShellExecutable(env: ["SHELL": "/this/path/does/not/exist"])
        #expect(picked == "/bin/zsh")
    }
}

@Suite("UserShellPath.runShellAndExtractPath")
struct UserShellPathSubprocessTests {

    private static let sh = URL(fileURLWithPath: "/bin/sh")
    private static let begin = "__B__"
    private static let end = "__E__"

    @Test("returns the value between markers from a healthy script")
    func happyPath() {
        let path = UserShellPath.runShellAndExtractPath(
            executable: Self.sh,
            arguments: ["-c", "printf '%s%s%s' '\(Self.begin)' '/a:/b:/c' '\(Self.end)'"],
            begin: Self.begin,
            end: Self.end,
            timeout: 2.0
        )
        #expect(path == "/a:/b:/c")
    }

    @Test("returns nil when the script exits non-zero")
    func nonZeroExitReturnsNil() {
        let path = UserShellPath.runShellAndExtractPath(
            executable: Self.sh,
            arguments: ["-c", "printf '%s%s%s' '\(Self.begin)' '/a:/b' '\(Self.end)'; exit 7"],
            begin: Self.begin,
            end: Self.end,
            timeout: 2.0
        )
        #expect(path == nil)
    }

    @Test("returns nil when the end marker is missing from stdout")
    func missingEndMarkerReturnsNil() {
        let path = UserShellPath.runShellAndExtractPath(
            executable: Self.sh,
            arguments: ["-c", "printf '%s%s' '\(Self.begin)' '/a:/b'"],
            begin: Self.begin,
            end: Self.end,
            timeout: 2.0
        )
        #expect(path == nil)
    }

    @Test("kills the subprocess and returns nil after the timeout")
    func timeoutReturnsNilAndKillsProcess() {
        let start = Date()
        let path = UserShellPath.runShellAndExtractPath(
            executable: Self.sh,
            arguments: ["-c", "sleep 5"],
            begin: Self.begin,
            end: Self.end,
            timeout: 0.3
        )
        let elapsed = Date().timeIntervalSince(start)
        #expect(path == nil)
        // Should return shortly after the deadline, not after the full 5s
        // sleep. The polling tick is 20 ms, so allow generous headroom.
        #expect(elapsed < 1.5)
    }

    @Test("stderr noise does not pollute stdout parsing")
    func stderrIsIgnored() {
        let path = UserShellPath.runShellAndExtractPath(
            executable: Self.sh,
            arguments: [
                "-c",
                "echo noise >&2; printf '%s%s%s' '\(Self.begin)' '/x' '\(Self.end)'",
            ],
            begin: Self.begin,
            end: Self.end,
            timeout: 2.0
        )
        #expect(path == "/x")
    }
}
