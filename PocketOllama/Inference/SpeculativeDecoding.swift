import Foundation

/// Speculative-decoding arithmetic, dependency-free so the CI self-check compiles
/// THIS file and exercises it against a copy that cannot drift from what ships.
///
/// The algorithm is the one in llama.cpp's `examples/speculative/speculative.cpp`,
/// verified against the pinned b11218 source:
///
///   1. A small draft model proposes K tokens cheaply.
///   2. The target model verifies all K in a SINGLE forward pass.
///   3. Each drafted token is accepted when `r <= p_tgt / p_dft`, with `r`
///      uniform in [0,1).
///   4. On the first rejection, the residual distribution
///      `max(0, p_tgt - p_dft)`, renormalised, is sampled instead, and the round
///      ends.
///
/// Step 3 is what makes this safe: it is standard rejection sampling, so the
/// emitted token sequence has the SAME distribution as the target model running
/// alone. It is a speed optimisation with no change to output quality.
///
/// Everything here is pure arithmetic on probability arrays. The llama.cpp calls
/// needed to produce those arrays (`llama_decode`, `llama_get_logits`,
/// `llama_memory_seq_*`) all exist in the XCFramework the app already ships, so
/// this needs no custom framework build and no RPC.
public enum SpeculativeDecoding {

    /// Outcome of verifying one drafted token.
    public enum Decision: Equatable {
        /// The drafted token is accepted; keep going.
        case accept
        /// Rejected. Emit a token sampled from the residual distribution and end
        /// the round.
        case reject(residual: [Float])
    }

    /// Softmax over raw logits, numerically stable.
    public static func softmax(_ logits: [Float]) -> [Float] {
        guard let maxLogit = logits.max() else { return [] }
        var exps = [Float](repeating: 0, count: logits.count)
        var sum: Float = 0
        for (i, l) in logits.enumerated() {
            let e = exp(l - maxLogit)
            exps[i] = e
            sum += e
        }
        guard sum > 0, sum.isFinite else {
            // Degenerate input: fall back to a uniform distribution rather than
            // dividing by zero and producing NaN, which would silently poison
            // every later comparison.
            let n = Float(max(1, logits.count))
            return [Float](repeating: 1.0 / n, count: logits.count)
        }
        return exps.map { $0 / sum }
    }

    /// Decide whether to accept the drafted token.
    ///
    /// - Parameters:
    ///   - pTarget: target model's probability of the drafted token
    ///   - pDraft:  draft model's probability of the same token
    ///   - residual: the target distribution minus the draft distribution, used
    ///     only when the token is rejected
    ///   - u: uniform draw in [0,1)
    ///
    /// A draft probability of zero means the draft assigned this token no chance.
    /// Accepting unconditionally is the correct limit: the ratio is unbounded, and
    /// rejecting would be a silent bias against exactly the tokens a good draft
    /// model discovers.
    public static func decide(pTarget: Float, pDraft: Float,
                              residual: [Float], u: Float) -> Decision {
        guard pTarget.isFinite, pDraft.isFinite, u.isFinite else {
            return .accept
        }
        if pDraft <= 0 { return .accept }
        if pTarget <= 0 { return .reject(residual: residual) }
        if u <= pTarget / pDraft { return .accept }
        return .reject(residual: residual)
    }

    /// `max(0, p_tgt - p_dft)` over the whole vocabulary, renormalised to sum to 1.
    ///
    /// This is the residual distribution the original samples from on rejection.
    /// Renormalising matters: without it the values are not a distribution and
    /// sampling from them is meaningless.
    public static func residual(target: [Float], draft: [Float]) -> [Float] {
        guard target.count == draft.count, !target.isEmpty else { return target }
        var out = [Float](repeating: 0, count: target.count)
        var sum: Float = 0
        for i in 0..<target.count {
            let d = target[i] - draft[i]
            let clamped = d > 0 ? d : 0
            out[i] = clamped
            sum += clamped
        }
        guard sum > 0, sum.isFinite else {
            // Every entry was clamped away, which happens when the draft
            // distribution dominates the target everywhere. Falling back to the
            // target distribution keeps the sampler well-defined.
            return normalised(target)
        }
        for i in 0..<out.count { out[i] = out[i] / sum }
        return out
    }

    /// Forces a distribution to sum to 1.0, or returns uniform if it cannot be.
    public static func normalised(_ probs: [Float]) -> [Float] {
        guard !probs.isEmpty else { return [] }
        let sum = probs.reduce(Float(0), +)
        guard sum > 0, sum.isFinite else {
            let n = Float(probs.count)
            return [Float](repeating: 1.0 / n, count: probs.count)
        }
        return probs.map { $0 / sum }
    }

    /// Sample an index from a distribution given a uniform draw in [0,1).
    /// Inverse-CDF: exact, no rejection loop.
    public static func sampleIndex(from probs: [Float], u: Float) -> Int {
        guard !probs.isEmpty else { return 0 }
        let clamped = u.isFinite ? min(max(u, 0), 0.999999) : 0
        var acc: Float = 0
        for (i, p) in probs.enumerated() {
            acc += p
            if clamped < acc { return i }
        }
        // Floating-point shortfall: the last valid index is the right answer.
        return probs.count - 1
    }

    /// Expected tokens emitted per target forward pass, for analysis and for
    /// deciding whether speculation is worth its overhead on this device.
    ///
    /// With acceptance rate `a` and `k` drafts per round, the expected number of
    /// accepted drafts is `(1 - a^(k+1)) / (1 - a)`, and one further token comes
    /// from the round's final forward pass.
    public static func expectedTokensPerPass(acceptanceRate a: Float, draftsPerRound k: Int) -> Float {
        guard k > 0 else { return 1 }
        guard a < 1 else { return Float(k) + 1 }
        guard a > 0 else { return 1 }
        let fk = Float(k)
        let accepted = (1 - pow(a, fk + 1)) / (1 - a)
        return accepted + 1
    }

    /// Whether speculation is worth enabling on a device with this much free RAM.
    ///
    /// Two models must be resident, so it only pays off where the draft is much
    /// smaller than the target. Below this floor the extra residency costs more
    /// than the accepted drafts save.
    public static func isWorthwhile(freeRAMBytes: UInt64,
                                    targetModelBytes: UInt64,
                                    draftModelBytes: UInt64) -> Bool {
        guard freeRAMBytes > 0 else { return false }
        let needed = targetModelBytes + draftModelBytes
        // Leave 350 MB for the kernel, GPU working set and fragmentation, the same
        // margin the rest of the app uses.
        let margin: UInt64 = 350 * 1024 * 1024
        guard freeRAMBytes > needed + margin else { return false }
        // A draft as large as the target saves nothing and doubles residency.
        return draftModelBytes * 4 <= targetModelBytes
    }
}
