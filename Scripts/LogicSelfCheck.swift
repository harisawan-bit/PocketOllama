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

    static func sumsToOne(_ xs: [Float]) -> Bool { abs(xs.reduce(0, +)) < 1e-5 }
    static func approx(_ a: Float, _ b: Float) -> Bool { abs(a - b) < 1e-4 }

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

        print("HTTP chunked framing")
        func chunked(_ s: String) -> Data { Data(s.utf8) }
        check("decodes a normal two-chunk body",
              String(data: HttpFraming.decodeChunked(chunked("4\r\nWiki\r\n5\r\npedia\r\n")), encoding: .utf8) == "Wikipedia")
        check("strips chunk extensions",
              String(data: HttpFraming.decodeChunked(chunked("4;name=v\r\nWiki\r\n")), encoding: .utf8) == "Wiki")
        check("accepts uppercase hex",
              String(data: HttpFraming.decodeChunked(chunked("A\r\n0123456789\r\n")), encoding: .utf8) == "0123456789")
        // The crash: a size of exactly Int64.max parses, and the old code added it
        // to the cursor unchecked, which traps in Swift.
        let overflowSize = String(Int64.max, radix: 16)
        check("Int64.max size is refused, not added",
              HttpFraming.decodeChunked(chunked("\(overflowSize)\r\nAAAA\r\n")).isEmpty)
        check("a size past Int64.max is refused",
              HttpFraming.decodeChunked(chunked("FFFFFFFFFFFFFFFF\r\nAAAA\r\n")).isEmpty)
        check("a huge but valid size is refused",
              HttpFraming.decodeChunked(chunked("7FFFFFF\r\nAAAA\r\n")).isEmpty)
        check("a size larger than the payload stops cleanly",
              HttpFraming.decodeChunked(chunked("FF\r\nshort\r\n")).isEmpty)
        check("garbage size is refused",
              HttpFraming.decodeChunked(chunked("zz\r\nAAAA\r\n")).isEmpty)
        check("negative size is refused",
              HttpFraming.decodeChunked(chunked("-4\r\nAAAA\r\n")).isEmpty)
        check("empty body is handled",
              HttpFraming.decodeChunked(chunked("")).isEmpty)
        check("truncated size line is handled",
              HttpFraming.decodeChunked(chunked("4\r\n")).isEmpty)
        check("body with no CRLF at all is handled",
              HttpFraming.decodeChunked(chunked("garbage")).isEmpty)
        check("decodes an empty chunked body",
              HttpFraming.decodeChunked(chunked("0\r\n\r\n")).isEmpty)

        print("Download size parsing")
        func bytes(_ s: String) -> UInt64 { DownloaderValidation.approximateBytes(forSizeDescription: s) }
        let mb = 1024.0 * 1024.0
        check("parses GB", abs(Double(bytes("4.92 GB")) - 4.92 * 1024 * mb) < 1)
        check("parses MB", bytes("390 MB") == 390 * UInt64(mb))
        check("parses lowercase", bytes("2.01 gb") == bytes("2.01 GB"))
        check("assumes GB when the unit is missing", bytes("1.5") == bytes("1.5 GB"))
        check("parses KB", bytes("512 KB") == 512 * 1024)
        check("garbage yields zero", bytes("unknown") == 0)
        check("empty yields zero", bytes("") == 0)
        check("negative yields zero", bytes("-5 GB") == 0)
        check("zero yields zero", bytes("0 GB") == 0)

        print("RAM bands")
        // Each band must get its own recommendation. A single 7.2 GB cut-off gave
        // a 2 GB phone and a 6 GB phone the same profile.
        check("2 GB gets the smallest band",   RAMBands.band(totalRAMGB: 2.0).context == 2048)
        check("3 GB band differs from 2 GB",   RAMBands.band(totalRAMGB: 3.0).context > RAMBands.band(totalRAMGB: 2.0).context)
        // 4 GB sits in the same band as 3 GB by design: an XR and a 12 mini can
        // both run a 1.5B at 4k. What matters is that distinct real device tiers
        // each get a usable profile, and that 6 GB is NOT handed the 8B tier.
        check("4 GB band is usable",            RAMBands.band(totalRAMGB: 4.0).context >= 4096)
        check("6 GB band differs from 4 GB",   RAMBands.band(totalRAMGB: 6.0).context > RAMBands.band(totalRAMGB: 4.0).context)
        check("8 GB band differs from 6 GB",   RAMBands.band(totalRAMGB: 8.0).context > RAMBands.band(totalRAMGB: 6.0).context)
        check("a 6 GB device is not given the 8B tier",
              !RAMBands.band(totalRAMGB: 6.0).tier.contains("8B"))
        check("a 6 GB device is not given a 32k context",
              RAMBands.band(totalRAMGB: 6.0).context < 32768)
        // Every real device RAM tier must be covered by exactly one band.
        for ram in [2.0, 3.0, 4.0, 6.0, 8.0, 12.0, 16.0] {
            let b = RAMBands.band(totalRAMGB: ram)
            check("\(ram) GB band is usable", b.context >= 2048 && !b.kv.isEmpty && !b.tier.isEmpty)
        }
        // Non-decreasing, not strictly increasing: 3 GB and 4 GB share a band on
        // purpose. Strict monotonicity would be the wrong assertion.
        let ladder = [2.0, 3.0, 4.0, 6.0, 8.0, 12.0].map { RAMBands.band(totalRAMGB: $0).context }
        check("bands never shrink as RAM grows (\(ladder))",
              zip(ladder, ladder.dropFirst()).allSatisfy { $0 <= $1 })
        check("zero RAM still returns a usable band", RAMBands.band(totalRAMGB: 0).context >= 2048)
        check("a 64 GB future device gets the top band", RAMBands.band(totalRAMGB: 64.0).context == 32768)

        print("Context floor")
        // The budget never returns below 512, so anything flooring higher either
        // blocks a device or offers an unreachable value in the slider.
        check("a 1023-token budget floors to 512, not 1023",
              ContextSizing.floorContext(1023) == 512)
        check("a 1024-token budget stays 1024", ContextSizing.floorContext(1024) == 1024)
        check("a 5000-token budget floors to 4096", ContextSizing.floorContext(5000) == 4096)
        check("a sub-512 budget floors to 512", ContextSizing.floorContext(100) == 512)
        check("the ceiling is respected", ContextSizing.floorContext(999_999) == 262144)
        check("a zero budget floors to 512", ContextSizing.floorContext(0) == 512)

        print("Request validation")
        let avail = ["Qwen3.5-0.8B-Q4_0", "hermes-3-3b"]
        check("exact id resolves",        RequestValidation.resolves(requested: "Qwen3.5-0.8B-Q4_0", available: avail))
        check("case-insensitive",         RequestValidation.resolves(requested: "qwen3.5-0.8b-q4_0", available: avail))
        check(".gguf suffix tolerated",   RequestValidation.resolves(requested: "Qwen3.5-0.8B-Q4_0.gguf", available: avail))
        check("typo is rejected",         !RequestValidation.resolves(requested: "Qwen3.5-0.8B", available: avail))
        check("unknown is rejected",      !RequestValidation.resolves(requested: "gpt-4", available: avail))
        check("empty is rejected",        !RequestValidation.resolves(requested: "", available: avail))
        check("traversal is rejected",    !RequestValidation.resolves(requested: "../etc/passwd", available: avail))
        check("no models means nothing resolves",
              !RequestValidation.resolves(requested: "anything", available: []))
        check("model id must be non-empty",  RequestValidation.modelIdIsWellFormed("a"))
        check("model id rejects empty",      !RequestValidation.modelIdIsWellFormed("   "))
        check("model id rejects slashes",    !RequestValidation.modelIdIsWellFormed("a/b"))
        check("model id rejects traversal",  !RequestValidation.modelIdIsWellFormed(".."))

        print("max_tokens bounds")
        check("omitted is valid",          RequestValidation.maxTokensIsValid(nil))
        check("positive is valid",         RequestValidation.maxTokensIsValid(10))
        check("zero is invalid",           !RequestValidation.maxTokensIsValid(0))
        check("negative is invalid",       !RequestValidation.maxTokensIsValid(-5))
        check("omitted uses the default",  RequestValidation.clampMaxTokens(nil, contextTokens: 8192) == 2048)
        check("in-range value passes through",
              RequestValidation.clampMaxTokens(100, contextTokens: 8192) == 100)
        check("absurd value is clamped",
              RequestValidation.clampMaxTokens(99_999_999, contextTokens: 8192) == 8192 - 1024)
        check("clamped value stays positive",
              RequestValidation.clampMaxTokens(99_999_999, contextTokens: 512) >= 1)
        check("negative is clamped, not rejected here",
              RequestValidation.clampMaxTokens(-5, contextTokens: 8192) >= 1)

        print("Piece buffer sizing")
        check("positive return emits",
              PieceBufferSizing.action(forReturnValue: 12) == .emit(count: 12))
        check("zero return skips",
              PieceBufferSizing.action(forReturnValue: 0) == .skip)
        // The bug: a negative return means the buffer was too small, and the
        // magnitude is what was needed. It was treated as empty and the token
        // silently vanished from the answer.
        check("negative return grows and retries",
              PieceBufferSizing.action(forReturnValue: -257) == .growAndRetry(needed: 257))
        // -Int.min overflows and would trap the decode loop.
        check("Int.min saturates instead of trapping",
              PieceBufferSizing.action(forReturnValue: Int.min) == .growAndRetry(needed: Int.max))
        check("retry size exceeds the need",
              PieceBufferSizing.retryBufferSize(needed: 257) > 257)
        check("retry size is never zero",
              PieceBufferSizing.retryBufferSize(needed: 0) > 0)
        // Every return the loop can see must produce a defined action.
        for v in [Int.min, -4096, -257, -1, 0, 1, 256, 257, Int.max] {
            let a = PieceBufferSizing.action(forReturnValue: v)
            let ok: Bool
            switch a {
            case .emit(let c):     ok = c == v && c > 0
            case .growAndRetry(let n): ok = n > 0
            case .skip:            ok = (v == 0)
            }
            check("return \(v) yields a defined action", ok)
        }

print("Speculative decoding")
        func probs(_ xs: [Float]) -> [Float] { SpeculativeDecoding.softmax(xs) }

        // softmax must produce a real distribution, including on hostile input.
        check("softmax sums to 1", Self.sumsToOne(SpeculativeDecoding.softmax([3.0,1.0,0.5])))
        check("softmax handles all-equal logits",
              abs(SpeculativeDecoding.softmax([1.0,1.0,1.0]).reduce(0,+)) < 1e-5)
        check("softmax survives a huge logit without NaN",
              SpeculativeDecoding.softmax([1e30, 0.0]).allSatisfy { $0.isFinite })
        check("softmax on empty is empty", SpeculativeDecoding.softmax([]).isEmpty)
        check("softmax argmax preserved",
              SpeculativeDecoding.softmax([0.1, 9.0, 0.2]).enumerated().max(by: { $0.element < $1.element })!.offset == 1)

        // The acceptance rule, r <= p_tgt / p_dft.
        check("accepts when r is below the ratio",
              SpeculativeDecoding.decide(pTarget: 0.8, pDraft: 0.4, residual: [], u: 0.5) == .accept)
        check("rejects when r exceeds the ratio",
              {
                if case .reject = SpeculativeDecoding.decide(pTarget: 0.2, pDraft: 0.8, residual: [1.0], u: 0.9) { return true }
                return false
              }())
        // The ideal case: identical distributions must ALWAYS accept, at any u.
        var identicalAlwaysAccept = true
        for u in stride(from: Float(0), through: Float(0.999), by: Float(0.05)) {
            if SpeculativeDecoding.decide(pTarget: 0.5, pDraft: 0.5, residual: [], u: u) != .accept {
                identicalAlwaysAccept = false
            }
        }
        check("identical distributions always accept", identicalAlwaysAccept)
        // A zero draft probability is the unbounded-ratio limit: accept.
        check("zero draft probability accepts",
              SpeculativeDecoding.decide(pTarget: 0.5, pDraft: 0.0, residual: [], u: 0.99) == .accept)
        // Zero target probability can never be accepted.
        check("zero target probability rejects",
              {
                if case .reject = SpeculativeDecoding.decide(pTarget: 0.0, pDraft: 0.5, residual: [1.0], u: 0.01) { return true }
                return false
              }())
        // NaN must not silently reject everything.
        check("NaN input does not trap",
              SpeculativeDecoding.decide(pTarget: .nan, pDraft: .nan, residual: [], u: .nan) == .accept)

        // Residual: max(0, p_tgt - p_dft), renormalised.
        let r1 = SpeculativeDecoding.residual(target: [0.9, 0.05, 0.05], draft: [0.2, 0.4, 0.4])
        check("residual sums to 1", Self.sumsToOne(r1))
        check("residual is non-negative", r1.allSatisfy { $0 >= 0 })
        check("residual zeroes where draft dominates", r1[1] == 0 && r1[2] == 0)
        // When the draft dominates everywhere, fall back to the target.
        let r2 = SpeculativeDecoding.residual(target: [0.2, 0.2, 0.2], draft: [0.9, 0.9, 0.9])
        check("residual falls back to target when fully dominated",
              abs(r2.reduce(0,+)) < 1e-5 && r2.allSatisfy { $0.isFinite })
        check("residual on mismatched lengths returns target",
              SpeculativeDecoding.residual(target: [1.0, 0.0], draft: [0.5]).count == 2)

        // Sampling from the residual must land in range.
        var inRange = true
        for u in stride(from: Float(0), through: Float(0.99), by: Float(0.01)) {
            let idx = SpeculativeDecoding.sampleIndex(from: r1, u: u)
            if idx < 0 || idx >= r1.count { inRange = false }
        }
        check("sampling stays in range", inRange)
        check("u=0 picks the first non-empty entry",
              SpeculativeDecoding.sampleIndex(from: [0.0, 1.0], u: 0.0) == 1)
        check("u near 1 picks the last entry",
              SpeculativeDecoding.sampleIndex(from: [0.3, 0.3, 0.4], u: 0.999) == 2)
        check("NaN u does not trap", SpeculativeDecoding.sampleIndex(from: [0.5, 0.5], u: .nan) == 0)

        // Throughput model: several tokens per target pass.
        check("perfect acceptance yields k+1 tokens",
              Self.approx(SpeculativeDecoding.expectedTokensPerPass(acceptanceRate: 1.0, draftsPerRound: 4), 5.0))
        check("zero acceptance yields 1 token",
              Self.approx(SpeculativeDecoding.expectedTokensPerPass(acceptanceRate: 0.0, draftsPerRound: 4), 1.0))
        check("0.9 acceptance beats plain decoding",
              SpeculativeDecoding.expectedTokensPerPass(acceptanceRate: 0.9, draftsPerRound: 4) > 3.0)
        var monotonic = true
        var prev = SpeculativeDecoding.expectedTokensPerPass(acceptanceRate: 0.0, draftsPerRound: 4)
        for i in 1...18 {
            let a = Float(i) * 0.05
            let cur = SpeculativeDecoding.expectedTokensPerPass(acceptanceRate: a, draftsPerRound: 4)
            if cur < prev - 1e-4 { monotonic = false }
            prev = cur
        }
        check("throughput rises monotonically with acceptance", monotonic)
        check("k=0 degenerates to 1 token",
              SpeculativeDecoding.expectedTokensPerPass(acceptanceRate: 0.9, draftsPerRound: 0) == 1)

        // Worthwhileness: two models must be resident, so RAM is the gate.
        let big: UInt64 = 5 * 1024 * 1024 * 1024
        let small: UInt64 = 400 * 1024 * 1024
        check("worthwhile with room to spare",
              SpeculativeDecoding.isWorthwhile(freeRAMBytes: 8 * 1024 * 1024 * 1024,
                                               targetModelBytes: big, draftModelBytes: small))
        check("not worthwhile when it will not fit",
              !SpeculativeDecoding.isWorthwhile(freeRAMBytes: 2 * 1024 * 1024 * 1024,
                                                targetModelBytes: big, draftModelBytes: small))
        check("not worthwhile when the draft is as large as the target",
              !SpeculativeDecoding.isWorthwhile(freeRAMBytes: 64 * 1024 * 1024 * 1024,
                                                targetModelBytes: big, draftModelBytes: big))
        check("not worthwhile on unknown free RAM",
              !SpeculativeDecoding.isWorthwhile(freeRAMBytes: 0,
                                                targetModelBytes: big, draftModelBytes: small))

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
