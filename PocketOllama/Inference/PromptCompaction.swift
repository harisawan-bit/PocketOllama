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



/// The piece-buffer sizing rule, isolated so CI can test it.
///
/// `llama_token_to_piece` returns the byte count on success, and a NEGATIVE count
/// whose magnitude is the size the buffer needed. The decode loop treated any
/// non-positive value as "nothing to emit", which silently discarded tokens whose
/// piece exceeded the 256-byte buffer. That is what produced intermittent empty
/// answers: the tokens were generated, dropped, and never reported.
public enum PieceBufferSizing {
    /// What the loop should do with a given return value.
    public enum Action: Equatable {
        case emit(count: Int)
        case growAndRetry(needed: Int)
        case skip
    }

    public static func action(forReturnValue value: Int) -> Action {
        if value > 0 { return .emit(count: value) }
        // -value traps when value is Int.min, which a nonsense return could be.
        // Saturate instead of crashing the decode loop.
        if value < 0 {
            let needed = (value == Int.min) ? Int.max : -value
            return .growAndRetry(needed: needed)
        }
        return .skip
    }

    /// Size for a retry: the reported need plus slack so a second call does not
    /// come back needing exactly the same amount.
    public static func retryBufferSize(needed: Int) -> Int {
        max(needed + 8, 1)
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
