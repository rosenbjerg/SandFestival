import Foundation

enum HookEntryFactory {
    static let sourceSentinel = "?source=sand-festival"

    static func hookURL(port: UInt16) -> String {
        "http://127.0.0.1:\(port)/event\(sourceSentinel)"
    }

    static func entry(port: UInt16) -> [String: Any] {
        [
            "type": "http",
            "url": hookURL(port: port),
            "headers": ["Authorization": "Bearer $SAND_FESTIVAL_TOKEN"],
            "allowedEnvVars": ["SAND_FESTIVAL_TOKEN"],
        ]
    }

    static func isOurEntry(_ entry: [String: Any]) -> Bool {
        guard let url = entry["url"] as? String else { return false }
        return url.contains(sourceSentinel)
    }
}
