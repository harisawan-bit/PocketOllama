// Self-check for the non-obvious inference logic.
//
// Compiled together with the real PocketOllama/Inference/PromptCompaction.swift, so
// it exercises what actually ships rather than a copy that can silently drift.
//
//   swiftc PocketOllama/Inference/PromptCompaction.swift \
//          Scripts/LogicSelfCheck.swift -o /tmp/po-check && /tmp/po-check
import Foundation

/// Minimal stand-in so ModelBudget can be exercised without the real GGUF parser.
struct BudgetFixture: GGUFBudgetFields {
    var contextLengthTrained: Int
    var layerCount: Int
    var embeddingLength: Int
    var headCount: Int
    var headCountKV: Int
    var fileSizeBytes: UInt64

    init(_ ctx: Int, layers: Int = 32, embd: Int = 4096, heads: Int = 32, kvHeads: Int = 8, sizeGB: Double = 2.0) {
        self.contextLengthTrained = ctx
        self.layerCount = layers
        self.embeddingLength = embd
        self.headCount = heads
        self.headCountKV = kvHeads
        self.fileSizeBytes = UInt64(sizeGB * 1024 * 1024 * 1024)
    }
}

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



        print("ModelBudget")
        // head_dim is n_embd/n_head, so a GQA model must NOT be charged
        // n_embd/n_head_kv: that overstated the cache by the GQA factor.
        let gqa = BudgetFixture(8192, layers: 32, embd: 4096, heads: 32, kvHeads: 8)
        let perTok = ModelBudget.bytesPerToken(
            layerCount: gqa.layerCount, embeddingLength: gqa.embeddingLength,
            headCount: gqa.headCount, headCountKV: gqa.headCountKV, kvQuant: "q4_0")
        let expected = 2.0 * 32 * 8 * (4096.0 / 32.0) * 0.5625
        check("GQA head_dim uses n_head", abs(perTok - expected) < 0.001)

        // A model trained at 8k must never be offered more than 8k, even when
        // RAM would allow far more.
        let hugeRAM: UInt64 = 40 * 1024 * 1024 * 1024
        let ctx = ModelBudget.safeContextTokens(
            metadata: gqa, usableProcessRAMBytes: hugeRAM, safetyBufferBytes: 350 * 1024 * 1024, kvQuant: "q4_0")
        check("context capped at trained length (got \(ctx))", ctx <= 8192 && ctx >= 1024)

        // And a long-context model still gets its full trained range.
        let longCtx = BudgetFixture(131072, layers: 32, embd: 4096, heads: 32, kvHeads: 8)
        let ctx2 = ModelBudget.safeContextTokens(
            metadata: longCtx, usableProcessRAMBytes: hugeRAM, safetyBufferBytes: 350 * 1024 * 1024, kvQuant: "q4_0")
        check("long-context model keeps its range (got \(ctx2))", ctx2 > 8192)

        // When the model does not fit, the floor is returned rather than 0.
        let tinyRAM: UInt64 = 512 * 1024 * 1024
        let ctx3 = ModelBudget.safeContextTokens(
            metadata: gqa, usableProcessRAMBytes: tinyRAM, safetyBufferBytes: 350 * 1024 * 1024, kvQuant: "q4_0")
        check("no memory yields a positive floor (got \(ctx3))", ctx3 > 0 && ctx3 <= 8192)

        // KV quant recommendation must never claim more than the RAM can hold.
        for q in ["q8_0", "q4_0"] {
            let rec = ModelBudget.recommendKVQuant(
                metadata: gqa, desiredContext: 8192,
                usableProcessRAMBytes: 6 * 1024 * 1024 * 1024, safetyBufferBytes: 350 * 1024 * 1024)
            check("KV quant \(rec) is a known type", ["q8_0","q4_0","f16"].contains(rec))
        }
        check("q8_0 is chosen when there is abundant RAM",
              ModelBudget.recommendKVQuant(metadata: gqa, desiredContext: 2048,
                usableProcessRAMBytes: 40 * 1024 * 1024 * 1024, safetyBufferBytes: 0) == "q8_0")
        check("q4_0 is chosen when RAM is tight",
              ModelBudget.recommendKVQuant(metadata: gqa, desiredContext: 65536,
                usableProcessRAMBytes: 5 * 1024 * 1024 * 1024, safetyBufferBytes: 0) == "q4_0")

        print("GGUF validation")
        // A download that returns HTTP 200 with an HTML error or rate-limit page
        // used to be saved as <model>.gguf and only failed much later at load.
        check("real GGUF magic is accepted",
              DownloaderValidation.isGGUF(magic: [0x47, 0x47, 0x55, 0x46]))
        check("HTML error page is rejected",
              !DownloaderValidation.isGGUF(magic: Array("<!DOCTYPE h".utf8)))
        check("truncated file is rejected",
              !DownloaderValidation.isGGUF(magic: [0x47]))
        check("empty file is rejected",
              !DownloaderValidation.isGGUF(magic: []))
        check("wrong-but-plausible magic is rejected",
              !DownloaderValidation.isGGUF(magic: Array("PK\u{03}\u{04}".utf8)))

        print("Download path safety")
        // modelId became a filename unchecked; a separator escaped the models dir.
        check("slash in modelId is neutralised",
              DownloaderValidation.safeFileComponent("a/b") == "a_b")
        check("traversal is neutralised",
              !DownloaderValidation.safeFileComponent("../../etc/passwd").contains("/"))
        check("dot-dot is neutralised",
              !DownloaderValidation.safeFileComponent("..").contains(".."))
        check("ordinary name is preserved",
              DownloaderValidation.safeFileComponent("qwen2.5-0.5b") == "qwen2.5-0.5b")

        print("Stop-sequence matching")
        // The decode loop tests the suffix on the accumulated text. If this ever
        // regressed to testing a partial buffer, a stop token split across two
        // tokens would be missed and the answer would run on past it.
        // The real scenario: a stop token split across two decode steps must
        // still be caught once the second piece lands, and must not fire early.
        var acc = ""
        var firedAt: Int? = nil
        for (i, piece) in ["the answer is ", "ST", "OP", " and more"].enumerated() {
            acc += piece
            if firedAt == nil, StopMatching.match(acc, stopTokens: ["STOP"]) != nil {
                firedAt = i
            }
        }
        check("stop token split across pieces is caught (at \(firedAt.map(String.init) ?? "never"))",
              firedAt == 2)
        check("a stop token is only a suffix, never a substring",
              StopMatching.match("the answer is STOP and then more", stopTokens: ["STOP"]) == nil)
        check("no false positive without the token",
              StopMatching.match("the answer is finished", stopTokens: ["STOP"]) == nil)
        check("longest matching stop token wins",
              StopMatching.match("abc ENDING", stopTokens: ["END", "ENDING"]) == "ENDING")
        check("empty stop tokens never match",
              StopMatching.match("anything", stopTokens: ["", "  "]) == nil)

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
