import Foundation

struct HookPayload: Equatable {
    let sessionID: String
    let hookEventName: String
    let cwd: URL?
    let permissionMode: String?
    let notificationMessage: String?
    let stopReason: String?
    let toolName: String?
}

enum HookPayloadDecoder {
    static func decode(_ data: Data) -> HookPayload? {
        guard let raw = try? JSONSerialization.jsonObject(with: data),
              let json = raw as? [String: Any] else {
            return nil
        }
        return decode(json)
    }

    static func decode(_ json: [String: Any]) -> HookPayload? {
        guard let sessionID = json["session_id"] as? String, !sessionID.isEmpty,
              let hookEventName = json["hook_event_name"] as? String, !hookEventName.isEmpty else {
            return nil
        }
        return HookPayload(
            sessionID: sessionID,
            hookEventName: hookEventName,
            cwd: (json["cwd"] as? String).map { URL(fileURLWithPath: $0) },
            permissionMode: json["permission_mode"] as? String,
            notificationMessage: json["message"] as? String,
            stopReason: json["reason"] as? String,
            toolName: json["tool_name"] as? String
        )
    }
}
