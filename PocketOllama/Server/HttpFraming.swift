import Foundation

/// HTTP message framing helpers, dependency-free so the CI self-check can compile
/// THIS file and exercise it against hostile input.
public enum HttpFraming {
    /// No single chunk may exceed this. A chunk size is attacker-controlled, so it
    /// is rejected before any arithmetic is done with it.
    public static let maxChunkBytes = 64 * 1024 * 1024

    /// Decodes a chunked transfer body.
    ///
    /// Every index is computed with checked arithmetic. The previous version did
    /// `chunkStart + size` directly, which traps on overflow in Swift: a chunk
    /// size line of `7FFFFFFFFFFFFFFF` parses cleanly as `Int64.max` and then
    /// overflowed the addition. That was reachable from anything on the Wi-Fi,
    /// because `parseRequest` runs before the API key check.
    public static func decodeChunked(_ raw: Data) -> Data {
        var out = Data()
        var cursor = raw.startIndex

        while cursor < raw.endIndex {
            guard let lineEnd = raw[cursor...].range(of: Data("\r\n".utf8)) else { break }
            let sizeField = String(data: raw[cursor..<lineEnd.lowerBound], encoding: .utf8) ?? ""
            // Strip any chunk extension, e.g. "1a;name=value".
            let hex = sizeField.split(separator: ";").first.map(String.init) ?? ""
            guard let size = Int(hex, radix: 16), size > 0, size <= maxChunkBytes else { break }

            let chunkStart = lineEnd.upperBound
            let (chunkEnd, overflow) = chunkStart.addingReportingOverflow(size)
            guard !overflow, chunkEnd <= raw.endIndex else { break }
            out.append(raw[chunkStart..<chunkEnd])

            // Skip the CRLF after the chunk data, without running past the end.
            let (next, overflow2) = chunkEnd.addingReportingOverflow(2)
            if overflow2 || next > raw.endIndex { break }
            cursor = next
        }
        return out
    }
}
