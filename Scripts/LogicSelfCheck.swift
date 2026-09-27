// Self-check for the non-obvious inference logic. Compiled together with the real
// PocketOllama/Inference/PromptCompaction.swift, so it cannot drift from what ships.
//
//   swiftc PocketOllama/Inference/PromptCompaction.swift Scripts/LogicSelfCheck.swift -o /tmp/po-check
//   /tmp/po-check
import Foundation

var failures = 0
func check(_ name: String, _ condition: Bool) {
    print(condition ? "  ok   \(name)" : "  FAIL \(name)")
    if !condition { failures += 1 }
}

print("PartialUTF8Decoder")
do {
    // "e-acute" is 0xC3 0xA9. Split across two tokens it must survive intact.
    var d = PartialUTF8Decoder()
    d.append(contentsOf: [0xC3])
    let first = d.drainDecodable()
    d.append(contentsOf: [0xA9])
    let second = d.drainDecodable()
    check("holds a lone lead byte", first.isEmpty)
    check("completes on continuation", second == "\u{E9}")
    check("no replacement char", (first + second).unicodeScalars.allSatisfy { $0.value != 0xFFFD })
}
do {
    let bytes = Array("\u{1F642}".utf8)            // 4-byte emoji
    var d = PartialUTF8Decoder()
    var got = ""
    for b in bytes { d.append(contentsOf: [b]); got += d.drainDecodable() }
    check("4-byte emoji across 4 tokens", got == "\u{1F642}")
}
do {
    var d = PartialUTF8Decoder()
    d.append(contentsOf: Array("hello world".utf8))
    check("pure ASCII passes straight through", d.drainDecodable() == "hello world")
}
do {
    var d = PartialUTF8Decoder()
    d.append(contentsOf: Array("ok \u{2705}".utf8))
    check("mixed ASCII + multibyte", d.drainDecodable() == "ok \u{2705}")
}
do {
    // A stray continuation byte must not swallow the rest of the stream.
    var d = PartialUTF8Decoder()
    d.append(contentsOf: [0x80, 0x41])
    check("stray continuation byte survives", d.drainDecodable().count == 2)
}

print("PromptCompaction.compactTokenWindow")
do {
    let tokens = Array(1...1000)
    let out = PromptCompaction.compactTokenWindow(tokens, limit: 400)
    check("respects the limit", out.count <= 400)
    check("keeps the system prompt at the head", out[0] == 1 && out[9] == 10)
    check("keeps the question at the tail", out.last == 1000)
    check("injects no junk token", !out.contains(0))
}
do {
    let tokens = Array(1...100)
    check("no-op when already short", PromptCompaction.compactTokenWindow(tokens, limit: 400) == tokens)
}
do {
    let tokens = Array(1...1000)
    let out = PromptCompaction.compactTokenWindow(tokens, limit: 4)
    check("degrades safely on a tiny limit", out.count <= 4 && out.first == 1 && out.last == 1000)
}
do {
    check("no-op at limit zero", PromptCompaction.compactTokenWindow(Array(1...10), limit: 0) == Array(1...10))
}

print(failures == 0 ? "\nAll checks passed" : "\n\(failures) check(s) failed")
exit(failures == 0 ? 0 : 1)
