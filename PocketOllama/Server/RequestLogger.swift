import Foundation
import Combine

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
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: timestamp)
    }

    public var summary: String {
        var base = "[\(formattedTime)] \(method) \(path) -> \(statusCode)"
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

    public func clear() {
        DispatchQueue.main.async {
            self.recentLogs.removeAll()
        }
    }
}
