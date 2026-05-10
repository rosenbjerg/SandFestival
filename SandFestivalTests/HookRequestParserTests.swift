import Testing
@testable import SandFestival

@Suite("HookRequestParser")
struct HookRequestParserTests {

    @Test("parses request line and case-insensitive header fields")
    func parsesRequestLineAndFields() {
        let raw = "POST /event HTTP/1.1\r\nHost: 127.0.0.1\r\nAUTHORIZATION: Bearer abc\r\nContent-Length: 12"
        let headers = try? #require(HookRequestParser.parseHeaders(raw))
        #expect(headers?.requestLine == "POST /event HTTP/1.1")
        #expect(headers?.fields["host"] == "127.0.0.1")
        #expect(headers?.authorization == "Bearer abc")
        #expect(headers?.contentLength == 12)
    }

    @Test("returns nil for an empty header block")
    func returnsNilForEmptyHeaders() {
        #expect(HookRequestParser.parseHeaders("") == nil)
    }

    @Test("ignores garbage lines without a colon")
    func ignoresLinesWithoutColon() {
        let raw = "POST /event HTTP/1.1\r\ngarbage\r\nValid: yes"
        let headers = HookRequestParser.parseHeaders(raw)
        #expect(headers?.fields["valid"] == "yes")
        #expect(headers?.fields.count == 1)
    }

    @Test("missing Content-Length defaults to 0")
    func missingContentLengthIsZero() {
        let raw = "POST / HTTP/1.1\r\nHost: x"
        let headers = HookRequestParser.parseHeaders(raw)
        #expect(headers?.contentLength == 0)
    }

    @Test("authorization requires the exact `Bearer <token>` form")
    func authChecksExactBearerMatch() {
        let headers = HookRequestParser.Headers(
            requestLine: "POST / HTTP/1.1",
            fields: ["authorization": "Bearer secret"]
        )
        #expect(HookRequestParser.isAuthorized(headers: headers, expectedToken: "secret"))
        #expect(!HookRequestParser.isAuthorized(headers: headers, expectedToken: "other"))
    }

    @Test("requests without an Authorization header are rejected")
    func authFailsWithoutHeader() {
        let headers = HookRequestParser.Headers(requestLine: "POST / HTTP/1.1", fields: [:])
        #expect(!HookRequestParser.isAuthorized(headers: headers, expectedToken: "secret"))
    }

    @Test("a bare token without the `Bearer ` prefix is rejected")
    func authFailsForBareToken() {
        let headers = HookRequestParser.Headers(
            requestLine: "POST / HTTP/1.1",
            fields: ["authorization": "secret"]
        )
        #expect(!HookRequestParser.isAuthorized(headers: headers, expectedToken: "secret"))
    }
}
