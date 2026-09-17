import Foundation

enum HookEntryFactory {
    static let sourceSentinel = "?source=sand-festival"

    static let projectHeaderName = "X-Sand-Festival-Project"

    static func hookURL(port: UInt16) -> String {
        "http://127.0.0.1:\(port)/event\(sourceSentinel)"
    }

    static func entry(port: UInt16) -> [String: Any] {
        [
            "type": "command",
            "command": commandString(port: port),
        ]
    }

    static func isOurEntry(_ entry: [String: Any]) -> Bool {
        if let url = entry["url"] as? String, url.contains(sourceSentinel) {
            return true
        }
        if let command = entry["command"] as? String, command.contains(sourceSentinel) {
            return true
        }
        return false
    }

    private static func commandString(port: UInt16) -> String {
        let url = hookURL(port: port)
        return """
        curl --silent --show-error --max-time 1 \
        -X POST \
        -H "Authorization: Bearer $SAND_FESTIVAL_TOKEN" \
        -H "\(projectHeaderName): $SAND_FESTIVAL_PROJECT_ID" \
        -H "Content-Type: application/json" \
        --data-binary @- \
        "\(url)" \
        >/dev/null 2>&1 || true
        """
    }
}
