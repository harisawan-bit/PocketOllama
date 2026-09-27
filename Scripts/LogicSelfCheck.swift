// Assert-based self-check for the two pieces of non-obvious logic added in 2.5.0.
// Run: swift Scripts/LogicSelfCheck.swift   (no framework, no test runner)
import Foundation

var failures = 0
func check(_ name: String, _ condition: Bool) {
    print(condition ? "  ok   \(name)" : "  FAIL \(name)")
    if !condition { failures += 1 }
}

// MARK: - PartialUTF8Decoder
// A token boundary can land inside a multi-byte character. Decoding each token on
// its own yields U+FFFD; the decoder must hold the partial tail back.
struct PartialUTF8Decoder {
    private var pending: [UInt8] = []
    mutating func append<S: Sequence>(contentsOf bytes: S) where S.Element == UInt8 {
        pending.append(contentsOf: bytes)
    }
    mutating func drainDecodable() -> String {
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
            default: width = 1; valid = false
            }
            if !valid { out.append(Character(UnicodeScalar(b))); i += 1; continue }
            if i + width > pending.count { break }
            out.append(contentsOf: String(decoding: pending[i..<(i + width)], as: UTF8.self))
            i += width
        }
        pending.removeFirst(i)
        return out
    }
}

print("PartialUTF8Decoder")
do {
    // "é" is 0xC3 0xA9. Split across two appends it must survive intact.
    var d = PartialUTF8Decoder()
    d.append(contentsOf: [0xC3])
    let first = d.drainDecodable()
    d.append(contentsOf: [0xA9])
    let second = d.drainDecodable()
    check("holds a lone lead byte", first.isEmpty)
    check("completes on continuation", second == "é")
    check("no replacement char", (first + second).unicodeScalars.allSatisfy { $0.value != 0xFFFD })
}
do {
    // A 4-byte emoji delivered one byte at a time.
    let bytes = Array("🙂".utf8)
    var d = PartialUTF8Decoder()
    var got = ""
    for b in bytes { d.append(contentsOf: [b]); got += d.drainDecodable() }
    check("4-byte emoji across 4 tokens", got == "🙂")
}
do {
    var d = PartialUTF8Decoder()
    d.append(contentsOf: Array("hello world".utf8))
    check("pure ASCII passes straight through", d.drainDecodable() == "hello world")
}
do {
    // Mixed ASCII and multi-byte in a single piece.
    var d = PartialUTF8Decoder()
    d.append(contentsOf: Array("ok ✅".utf8))
    check("mixed ASCII + multibyte", d.drainDecodable() == "ok ✅")
}

// MARK: - middle-out prompt compaction
// Dropping tokens from the front deletes the system prompt and the opening turns,
// which makes the model answer the wrong question. The head and tail must survive.
func compactTokenWindow(_ tokens: [Int], limit: Int) -> [Int] {
    guard tokens.count > limit, limit > 0 else { return tokens }
    let headCount = max(1, limit / 4)
    let tailCount = max(1, limit - headCount - 1)
    return Array(tokens.prefix(headCount)) + [0] + Array(tokens.suffix(tailCount))
}

print("middle-out compaction")
do {
    let tokens = Array(1...1000)
    let out = compactTokenWindow(tokens, limit: 400)
    check("respects the limit", out.count <= 400)
    check("keeps the system prompt at the head", out[0] == 1 && out[9] == 10)
    check("keeps the question at the tail", out.last == 1000)
    check("marks the cut", out.contains(0))
}
do {
    let tokens = Array(1...100)
    check("no-op when already short", compactTokenWindow(tokens, limit: 400) == tokens)
}
do {
    let tokens = Array(1...1000)
    let out = compactTokenWindow(tokens, limit: 4)
    check("degrades safely on a tiny limit", out.count <= 4 && out.first == 1 && out.last == 1000)
}

print(failures == 0 ? "\nAll checks passed" : "\n\(failures) check(s) failed")
exit(failures == 0 ? 0 : 1)
