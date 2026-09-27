// Self-check for the non-obvious inference logic.
//
// Compiled together with the real PocketOllama/Inference/PromptCompaction.swift, so
// it exercises what actually ships rather than a copy that can silently drift.
//
//   swiftc PocketOllama/Inference/PromptCompaction.swift \
//          Scripts/LogicSelfCheck.swift -o /tmp/po-check && /tmp/po-check
import Foundation

@main
struct LogicSelfCheck {
    static var failures = 0

    static func check(_ name: String, _ condition: Bool) {
        print(condition ? "  ok   \(name)" : "  FAIL \(name)")
        if !condition { failures += 1 }
    }

    static func main() {
        print("PartialUTF8Decoder")
        // "e with acute" is 0xC3 0xA9. Split across two tokens it must survive intact.
        var d = PartialUTF8Decoder()
        d.append(contentsOf: [0xC3])
        let first = d.drainDecodable()
        d.append(contentsOf: [0xA9])
        let second = d.drainDecodable()
        check("holds a lone lead byte", first.isEmpty)
        check("completes on continuation", second == "\u{E9}")
        check("no replacement char", (first + second).unicodeScalars.allSatisfy { $0.value != 0xFFFD })

        // A 4-byte emoji delivered one byte per token.
        let emoji = Array("\u{1F642}".utf8)
        var d2 = PartialUTF8Decoder()
        var got = ""
        for b in emoji { d2.append(contentsOf: [b]); got += d2.drainDecodable() }
        check("4-byte emoji across 4 tokens", got == "\u{1F642}")

        var d3 = PartialUTF8Decoder()
        d3.append(contentsOf: Array("hello world".utf8))
        check("pure ASCII passes straight through", d3.drainDecodable() == "hello world")

        var d4 = PartialUTF8Decoder()
        d4.append(contentsOf: Array("ok \u{2705}".utf8))
        check("mixed ASCII + multibyte", d4.drainDecodable() == "ok \u{2705}")

        // A stray continuation byte must not swallow the rest of the stream.
        var d5 = PartialUTF8Decoder()
        d5.append(contentsOf: [0x80, 0x41])
        check("stray continuation byte survives", d5.drainDecodable().count == 2)

        print("PromptCompaction.compactTokenWindow")
        let tokens = Array(1...1000)
        let out = PromptCompaction.compactTokenWindow(tokens, limit: 400)
        check("respects the limit", out.count <= 400)
        check("keeps the system prompt at the head", out[0] == 1 && out[9] == 10)
        check("keeps the question at the tail", out.last == 1000)
        check("injects no junk token", !out.contains(0))

        let short = Array(1...100)
        check("no-op when already short", PromptCompaction.compactTokenWindow(short, limit: 400) == short)

        let tiny = PromptCompaction.compactTokenWindow(tokens, limit: 4)
        check("degrades safely on a tiny limit", tiny.count <= 4 && tiny.first == 1 && tiny.last == 1000)

        check("no-op at limit zero", PromptCompaction.compactTokenWindow(short, limit: 0) == short)


        print("ContextSizing")
        // Every value offered in the prefill batch picker must satisfy the
        // n_ubatch <= n_batch invariant, or the context fails to initialise and
        // no model will load at all.
        for candidate in [128, 256, 512, 1024] {
            let s = ContextSizing.batchSizes(prefillBatch: candidate)
            check("prefill \(candidate): ubatch \(s.ubatch) <= batch \(s.batch)", s.ubatch <= s.batch && s.ubatch > 0)
        }
        do {
            // Hostile inputs must not produce a zero or negative size.
            for bad in [0, -5, 1, 99999] {
                let s = ContextSizing.batchSizes(prefillBatch: bad)
                check("prefill \(bad) stays valid", s.batch >= 512 && s.ubatch > 0 && s.ubatch <= s.batch)
            }
        }
        check("threads respect the thermal cap",
              ContextSizing.effectiveThreads(configured: 6, thermalCap: 2) == 2)
        check("threads use the configured value when cool",
              ContextSizing.effectiveThreads(configured: 6, thermalCap: 6) == 6)
        check("threads never reach zero",
              ContextSizing.effectiveThreads(configured: 0, thermalCap: 0) == 1)

        print(failures == 0 ? "\nAll checks passed" : "\n\(failures) check(s) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
