import Foundation

/// Pure helpers for the inference hot path, kept dependency-free so the CI
/// self-check can compile THIS file directly rather than a copy that can drift
/// away from what actually ships.
public enum PromptCompaction {
    /// Trims an over-long prompt by dropping tokens from the middle, keeping the
    /// head (system instructions) and the tail (the user's actual question).
    /// Truncating from the front instead silently deleted the system prompt and
    /// the opening turns, which made the model answer the wrong thing.
    ///
    /// No separator is inserted: token 0 is <unk> in most vocabs and feeding it
    /// into the middle of a prompt can corrupt generation.
    public static func compactTokenWindow<T>(_ tokens: [T], limit: Int) -> [T] {
        guard tokens.count > limit, limit > 0 else { return tokens }
        let headCount = max(1, limit / 4)
        return Array(tokens.prefix(headCount)) + Array(tokens.suffix(limit - headCount))
    }
}

/// Accumulates token bytes and emits only complete UTF-8 sequences.
/// A token boundary can fall inside a multi-byte character; decoding each token
/// alone yields U+FFFD for any non-ASCII output.
public struct PartialUTF8Decoder {
    private var pending: [UInt8] = []

    public init() {}

    public mutating func append<S: Sequence>(contentsOf bytes: S) where S.Element == UInt8 {
        pending.append(contentsOf: bytes)
    }

    /// Emits every complete sequence and retains a trailing partial one.
    public mutating func drainDecodable() -> String {
        var out = ""
        var i = 0
        while i < pending.count {
            let b = pending[i]
            let width: Int
            var valid = true
            switch b {
            case 0x00...0x7F: width = 1
            case 0xC2...0xDF: width = 2
            case 0xE0...0xEF: width = 3
            case 0xF0...0xF4: width = 4
            default: width = 1; valid = false   // stray lead or continuation byte
            }
            if !valid {
                out.append(Character(UnicodeScalar(b)))
                i += 1
                continue
            }
            if i + width > pending.count { break }   // incomplete, wait for the next token
            out.append(contentsOf: String(decoding: pending[i..<(i + width)], as: UTF8.self))
            i += width
        }
        pending.removeFirst(i)
        return out
    }
}


/// Stop-sequence matching over the accumulated answer.
///
/// Extracted so the CI self-check compiles the real implementation. The decode
/// loop relies on this testing a suffix that can span two tokens.
public enum StopMatching {
    /// Returns the stop token that `text` ends with, longest first so a longer
    /// token is not shadowed by a shorter one that is also a suffix.
    public static func match(_ text: String, stopTokens: [String]) -> String? {
        let candidates = stopTokens.filter { !$0.isEmpty }
        for token in candidates.sorted(by: { $0.count > $1.count }) {
            if text.hasSuffix(token) { return token }
        }
        return nil
    }
}
