import Foundation
import Combine
import Network

public struct LogEntry: Identifiable, Sendable {
    public let id = UUID()
    public let timestamp: Date
    public let method: String
    public let path: String
    public let clientIP: String
    public let statusCode: Int
    public let tokensGenerated: Int?
    public let durationSeconds: Double?
    public let tokensPerSecond: Double?

    public var formattedTime: String {
        LogEntry.timeFormatter.string(from: timestamp)
    }

    /// Static: this runs once per visible log row on every SwiftUI render.
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    public var summary: String {
        // clientIP was recorded on every row but never rendered, so the log gave
        // no way to tell which device made a request.
        var base = "[\(formattedTime)] \(clientIP) \(method) \(path) -> \(statusCode)"
        if let tokens = tokensGenerated, let speed = tokensPerSecond {
            base += " (\(tokens) tok, \(String(format: "%.1f", speed)) t/s)"
        }
        return base
    }
}

public final class RequestLogger: ObservableObject, @unchecked Sendable {
    public static let shared = RequestLogger()

    @Published public private(set) var recentLogs: [LogEntry] = []
    private let maxEntries = 50

    private init() {}

    public func log(
        method: String,
        path: String,
        clientIP: String = "127.0.0.1",
        statusCode: Int = 200,
        tokensGenerated: Int? = nil,
        durationSeconds: Double? = nil
    ) {
        let speed = (tokensGenerated != nil && durationSeconds != nil && durationSeconds! > 0)
            ? Double(tokensGenerated!) / durationSeconds!
            : nil

        let entry = LogEntry(
            timestamp: Date(),
            method: method,
            path: path,
            clientIP: clientIP,
            statusCode: statusCode,
            tokensGenerated: tokensGenerated,
            durationSeconds: durationSeconds,
            tokensPerSecond: speed
        )

        DispatchQueue.main.async {
            self.recentLogs.insert(entry, at: 0)
            if self.recentLogs.count > self.maxEntries {
                self.recentLogs.removeLast()
            }
        }
    }

    /// Real peer address for a connection.
    ///
    /// This used to return `endpoint.debugDescription`, which is a debug
    /// rendering (it embeds the endpoint's own state text) rather than an
    /// address, and it was stored on every log row.
    public func clientIP(for connection: NWConnection?) -> String {
        guard let connection else { return "unknown" }
        switch connection.endpoint {
        case let .hostPort(host, port):
            let raw = NWEndpoint.Host.debugDescription(host)
            // debugDescription renders as "192.168.1.5" or "host 192.168.1.5".
            let ip = raw.contains(" ") ? raw.split(separator: " ").last.map(String.init) ?? raw : raw
            return "\(ip):\(NWEndpoint.Port.debugDescription(port))"
        case let .service(name, _, _, _):
            return "service:\(name)"
        default:
            return "local"
        }
    }

    public func clear() {
        DispatchQueue.main.async {
            self.recentLogs.removeAll()
        }
    }
}
