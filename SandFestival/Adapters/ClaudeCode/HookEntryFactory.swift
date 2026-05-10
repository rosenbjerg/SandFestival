import Foundation

enum HookEntryFactory {
    static let sourceSentinel = "?source=sand-festival"

    static func hookURL(port: UInt16) -> String {
        "http://127.0.0.1:\(port)/event\(sourceSentinel)"
    }

    /// Returns the hook entry SandFestival ships in `~/.claude/settings.json`.
    /// Uses `type: "command"` rather than `type: "http"` so Claude Code never
    /// surfaces an ECONNREFUSED error when the dashboard isn't running —
    /// curl swallows its error stream and the trailing `|| true` forces a
    /// zero exit code so the hook is always considered successful.
    static func entry(port: UInt16) -> [String: Any] {
        [
            "type": "command",
            "command": commandString(port: port),
        ]
    }

    /// Recognizes either the legacy `type: "http"` entries (URL field) or the
    /// current `type: "command"` entries (command string contains the URL),
    /// keyed off the `?source=sand-festival` sentinel either way. This lets
    /// reinstall cleanly replace older formats.
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
        // 1s timeout keeps Claude Code's tool loop from blocking when the
        // dashboard is briefly unreachable. `|| true` swallows ECONNREFUSED
        // and any other curl exit code so the hook always reports success.
        // The Authorization header uses the env var SandFestival injects via
        // prepareSpawn — the shell expands it at hook-fire time.
        let url = hookURL(port: port)
        return """
        curl --silent --show-error --max-time 1 \
        -X POST \
        -H "Authorization: Bearer $SAND_FESTIVAL_TOKEN" \
        -H "Content-Type: application/json" \
        --data-binary @- \
        "\(url)" \
        >/dev/null 2>&1 || true
        """
    }
}
