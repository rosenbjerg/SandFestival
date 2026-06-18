import Foundation

enum HookRequestParser {
    struct Headers: Equatable {
        var requestLine: String
        var fields: [String: String]

        var contentLength: Int {
            Int(fields["content-length"] ?? "0") ?? 0
        }

        var authorization: String? {
            fields["authorization"]
        }

        /// The spawning project's id, forwarded by the hook command. Empty
        /// (the shell's expansion of an unset env var) reads as `nil` so a
        /// claude run outside SandFestival's spawn path doesn't carry one.
        var projectID: String? {
            let value = fields[HookEntryFactory.projectHeaderName.lowercased()]
            return (value?.isEmpty == false) ? value : nil
        }
    }

    /// Parses a CRLF-separated header block (everything before `\r\n\r\n`).
    /// Returns `nil` if the request line is missing or malformed.
    static func parseHeaders(_ raw: String) -> Headers? {
        let lines = raw.components(separatedBy: "\r\n")
        guard let requestLine = lines.first, !requestLine.isEmpty else { return nil }
        var fields: [String: String] = [:]
        for line in lines.dropFirst() where !line.isEmpty {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces).lowercased()
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            fields[key] = value
        }
        return Headers(requestLine: requestLine, fields: fields)
    }

    static func isAuthorized(headers: Headers, expectedToken: String) -> Bool {
        guard let auth = headers.authorization else { return false }
        return auth == "Bearer \(expectedToken)"
    }
}
