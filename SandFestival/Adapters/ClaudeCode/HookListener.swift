import Foundation
import Network
import os

enum HookListenerError: Error, Equatable {
    case bindFailed(port: UInt16)
    case invalidPort
}

/// Listens on `127.0.0.1:HookListener.port` for HTTP POSTs from Claude Code's
/// hook handlers. The port is fixed: a stable value lets the hook entries in
/// `~/.claude/settings.json` stay correct across app restarts without
/// rewriting on every launch. If the port is already in use the listener
/// surfaces a `bindFailed` error rather than wandering to another port.
final class HookListener: @unchecked Sendable {
    /// Picked once for SandFestival; changing this forces every hook entry
    /// to be rewritten, so don't change it lightly.
    static let port: UInt16 = 51789

    private let token: String
    private let onEvent: @Sendable (Data) -> Void
    private let queue = DispatchQueue(label: "app.sandfestival.claudecode.hooks")
    private var listener: NWListener?

    init(token: String, onEvent: @escaping @Sendable (Data) -> Void) {
        self.token = token
        self.onEvent = onEvent
    }

    /// Binds the listener to `HookListener.port`. Throws `.bindFailed` if the
    /// port is already in use.
    func start() async throws {
        guard await tryStart(port: HookListener.port) != nil else {
            throw HookListenerError.bindFailed(port: HookListener.port)
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    // MARK: - Listener lifecycle

    private func tryStart(port: UInt16) async -> UInt16? {
        await withCheckedContinuation { (continuation: CheckedContinuation<UInt16?, Never>) in
            guard let nwPort = NWEndpoint.Port(rawValue: port) else {
                continuation.resume(returning: nil)
                return
            }
            let parameters = NWParameters.tcp
            parameters.requiredInterfaceType = .loopback
            parameters.acceptLocalOnly = true
            parameters.allowLocalEndpointReuse = false

            let candidate: NWListener
            do {
                candidate = try NWListener(using: parameters, on: nwPort)
            } catch {
                continuation.resume(returning: nil)
                return
            }

            let resumed = ResumeFlag()
            candidate.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    if resumed.first() {
                        self?.listener = candidate
                        continuation.resume(returning: port)
                    }
                case .failed, .cancelled:
                    if resumed.first() {
                        candidate.cancel()
                        continuation.resume(returning: nil)
                    }
                default:
                    break
                }
            }
            candidate.newConnectionHandler = { [weak self] connection in
                self?.handle(connection: connection)
            }
            candidate.start(queue: queue)
        }
    }

    // MARK: - Per-connection HTTP handling

    private func handle(connection: NWConnection) {
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.readHeaders(connection: connection, accumulated: Data())
            case .failed, .cancelled:
                connection.cancel()
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    private func readHeaders(connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 16) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = accumulated
            if let data, !data.isEmpty { buffer.append(data) }

            if let headersEnd = HookListener.findHeadersEnd(in: buffer) {
                let headerBytes = buffer.prefix(headersEnd)
                let bodyStart = headersEnd + 4
                let bodySoFar = bodyStart < buffer.count ? buffer.suffix(from: bodyStart) : Data()
                let raw = String(data: headerBytes, encoding: .utf8) ?? ""
                self.dispatchAfterHeaders(connection: connection, headerString: raw, bodySoFar: bodySoFar)
            } else if error != nil || isComplete {
                connection.cancel()
            } else {
                self.readHeaders(connection: connection, accumulated: buffer)
            }
        }
    }

    private func dispatchAfterHeaders(connection: NWConnection, headerString: String, bodySoFar: Data) {
        guard let headers = HookRequestParser.parseHeaders(headerString) else {
            sendResponse(connection: connection, status: 400, reason: "Bad Request")
            return
        }
        guard HookRequestParser.isAuthorized(headers: headers, expectedToken: token) else {
            sendResponse(connection: connection, status: 401, reason: "Unauthorized")
            return
        }
        let target = headers.contentLength
        consumeBody(connection: connection, accumulated: bodySoFar, target: target)
    }

    private func consumeBody(connection: NWConnection, accumulated: Data, target: Int) {
        if accumulated.count >= target {
            let body = accumulated.prefix(target)
            onEvent(body)
            sendResponse(connection: connection, status: 200, reason: "OK")
            return
        }
        connection.receive(minimumIncompleteLength: 1, maximumLength: max(target - accumulated.count, 1)) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = accumulated
            if let data, !data.isEmpty { buffer.append(data) }
            if error != nil || (isComplete && buffer.count < target) {
                connection.cancel()
                return
            }
            self.consumeBody(connection: connection, accumulated: buffer, target: target)
        }
    }

    private func sendResponse(connection: NWConnection, status: Int, reason: String) {
        let body = "HTTP/1.1 \(status) \(reason)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(body.utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    // MARK: - Helpers

    private static let headerTerminator: [UInt8] = [0x0d, 0x0a, 0x0d, 0x0a]

    private static func findHeadersEnd(in data: Data) -> Int? {
        guard data.count >= 4 else { return nil }
        let bytes = [UInt8](data)
        let max = bytes.count - 4
        for index in 0...max where Array(bytes[index..<(index + 4)]) == headerTerminator {
            return index
        }
        return nil
    }
}

private final class ResumeFlag: @unchecked Sendable {
    private var fired = false
    private let lock = NSLock()

    func first() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !fired else { return false }
        fired = true
        return true
    }
}
