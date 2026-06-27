import Foundation
import Network

/// Shared port + token used by both the app and the installed HTTP hooks,
/// persisted to ~/.codepet/hook.json by install-hooks.js.
enum HookConfig {
    static let defaultPort: UInt16 = 51763

    static func load() -> (port: UInt16, token: String?) {
        guard let data = try? Data(contentsOf: Paths.hookFile),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return (defaultPort, nil)
        }
        let port = (obj["port"] as? Int).flatMap { UInt16(exactly: $0) } ?? defaultPort
        let token = obj["token"] as? String
        return (port, token)
    }
}

/// A tiny loopback-only HTTP/1.1 server. Claude Code's HTTP hooks POST event
/// JSON here; the body is handed to `onEvent`. Bound to 127.0.0.1, so it is not
/// reachable off-machine; an optional shared token guards against other local
/// processes spoofing events.
final class HookServer {
    private let port: UInt16
    private let token: String?
    private let onEvent: ([String: Any]) -> Void
    private let queue = DispatchQueue(label: "codepet.hookserver")
    private var listener: NWListener?

    /// Upper bound on a single request (headers + body). Hook payloads are small
    /// even with a big tool result; this just stops a buggy/hostile local client
    /// from growing the buffer without bound.
    private static let maxRequestBytes = 8 * 1024 * 1024
    /// Hard per-connection deadline so a stalled client can't pin a connection.
    private static let connectionTimeout: TimeInterval = 10

    init(port: UInt16, token: String?, onEvent: @escaping ([String: Any]) -> Void) {
        self.port = port
        self.token = token
        self.onEvent = onEvent
    }

    func start() {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        params.requiredInterfaceType = .loopback   // 127.0.0.1 only
        guard let nwPort = NWEndpoint.Port(rawValue: port),
              let listener = try? NWListener(using: params, on: nwPort) else {
            NSLog("CodePet: could not bind hook server on 127.0.0.1:\(port) — falling back to file watching")
            return
        }
        self.listener = listener
        listener.newConnectionHandler = { [weak self] conn in self?.accept(conn) }
        listener.start(queue: queue)
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    // MARK: - Connection handling

    private func accept(_ conn: NWConnection) {
        conn.start(queue: queue)
        // Cancel is idempotent, so a request that finishes earlier is unaffected;
        // this only reaps connections that stall before completing.
        queue.asyncAfter(deadline: .now() + HookServer.connectionTimeout) { [weak conn] in
            conn?.cancel()
        }
        receive(conn, buffer: Data())
    }

    private func receive(_ conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self = self else { conn.cancel(); return }
            var buffer = buffer
            if let data = data { buffer.append(data) }

            // Stop runaway buffers (missing terminator, oversized body).
            if buffer.count > HookServer.maxRequestBytes {
                self.sendStatusAndClose(conn, "413 Payload Too Large")
                return
            }

            if let (headerEnd, contentLength) = self.parseHeader(buffer) {
                // Reject nonsensical lengths instead of forming an invalid range.
                guard contentLength >= 0, contentLength <= HookServer.maxRequestBytes else {
                    self.sendStatusAndClose(conn, "413 Payload Too Large")
                    return
                }
                let available = buffer.count - headerEnd
                if available >= contentLength {
                    let body = contentLength > 0
                        ? buffer.subdata(in: headerEnd..<(headerEnd + contentLength))
                        : Data()
                    self.finish(conn, header: buffer.subdata(in: 0..<headerEnd), body: body)
                    return
                }
            }

            if isComplete || error != nil {
                self.finish(conn, header: buffer, body: Data())
                return
            }
            self.receive(conn, buffer: buffer)
        }
    }

    /// Locate the end of the HTTP header block and read Content-Length.
    private func parseHeader(_ buffer: Data) -> (end: Int, contentLength: Int)? {
        let sep = Data([13, 10, 13, 10]) // \r\n\r\n
        guard let range = buffer.range(of: sep) else { return nil }
        let header = String(decoding: buffer.subdata(in: 0..<range.lowerBound), as: UTF8.self)
        var contentLength = 0
        for line in header.components(separatedBy: "\r\n") {
            if line.lowercased().hasPrefix("content-length:") {
                let v = line.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)
                contentLength = Int(v) ?? 0
            }
        }
        return (range.upperBound, contentLength)
    }

    private func finish(_ conn: NWConnection, header: Data, body: Data) {
        let headerStr = String(decoding: header, as: UTF8.self).lowercased()
        var authorized = true
        if let token = token {
            authorized = headerStr.contains("x-codepet-token: \(token.lowercased())")
        }

        if authorized, !body.isEmpty,
           let obj = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
            onEvent(obj)
        }

        sendStatusAndClose(conn, authorized ? "200 OK" : "403 Forbidden")
    }

    /// Send a minimal HTTP response and close the connection.
    private func sendStatusAndClose(_ conn: NWConnection, _ status: String) {
        let response = "HTTP/1.1 \(status)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        conn.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
            conn.cancel()
        })
    }
}
