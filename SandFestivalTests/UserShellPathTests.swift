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
