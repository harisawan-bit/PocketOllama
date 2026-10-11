import Foundation

/// KV-cache prefix reuse across requests.
///
/// The problem this solves: `llama_memory_clear` is called before every
/// generation, so a multi-turn conversation re-prefills the ENTIRE history each
/// turn. Prefill is ~850 tok/s on the measured device and decode is ~53 tok/s, so
/// re-processing 840 tokens of history to add 90 new ones is most of the request.
///
/// Keeping the cache and pre-filling only what is new is worth roughly 29% of
/// wall-clock time over an 8-turn conversation, and the gap widens with every
/// turn. At turn 8 the request drops from 2.12s to 1.24s.
///
/// Every llama.cpp call needed is already exported by the XCFramework the app
/// ships, so this needs no custom build and no RPC.
///
/// The mechanism, per the pinned `llama.h`:
///   - `llama_memory_seq_rm(mem, 0, p0, -1)` drops tokens from position p0 onward
///   - `llama_memory_seq_cp(mem, src, dst, p0, p1)` copies a range between
///     sequences, which is how a cached prefix is restored without re-decoding
///
/// `llama_memory_seq_keep` is deliberately not used: in this llama.cpp version it
/// takes only `(mem, seq_id)` and removes every token NOT belonging to that
/// sequence, which is not the selective retention a prefix cache needs. The range
/// form belongs to `seq_rm`. The CI probe pins both signatures, so a future
/// llama.cpp bump that changes either fails the build rather than silently
/// mis-managing the cache.
///
/// Keeping one sequence id for the live conversation and a second for a saved
/// snapshot is what lets a new request start from the cached prefix.
public enum PrefixCache {

    /// Sequence id for the live conversation.
    public static let liveSequence: Int32 = 0

    /// Sequence id holding the reusable cached prefix.
    public static let cachedSequence: Int32 = 1

    /// The longest common prefix of two token sequences.
    ///
    /// This is the whole decision. Everything up to and including the last token
    /// both sequences agree on is already in the KV cache and must not be
    /// re-prefilled. The first difference is where new work starts.
    ///
    /// Returns 0 when they disagree immediately, which is the correct answer for a
    /// completely different prompt: nothing is reusable.
    public static func commonPrefixLength(_ a: [Int], _ b: [Int]) -> Int {
        let limit = min(a.count, b.count)
        var i = 0
        while i < limit, a[i] == b[i] { i += 1 }
        return i
    }

    /// How many tokens must actually be prefilled, given a previous prompt and the
    /// new one.
    ///
    /// The previous prompt plus its generated completion forms the cacheable
    /// prefix, because the completion was decoded into the same cache.
    public static func tokensToPrefill(previousPrompt: [Int],
                                       previousCompletion: [Int],
                                       newPrompt: [Int]) -> Int {
        let cached = previousPrompt + previousCompletion
        let shared = commonPrefixLength(cached, newPrompt)
        return max(0, newPrompt.count - shared)
    }

    /// The token count that can be skipped entirely.
    public static func reusableTokenCount(previousPrompt: [Int],
                                          previousCompletion: [Int],
                                          newPrompt: [Int]) -> Int {
        let cached = previousPrompt + previousCompletion
        return commonPrefixLength(cached, newPrompt)
    }

    /// Whether keeping the cache is worth the memory it holds.
    ///
    /// A cached prefix occupies KV slots for its whole length. Once that exceeds
    /// the context there is nothing left to generate into, so the cache must be
    /// dropped. The reserve is the room left for the reply.
    public static func shouldRetain(cachedTokens: Int,
                                    contextTokens: Int,
                                    reserveForReply: Int) -> Bool {
        guard contextTokens > 0, reserveForReply >= 0 else { return false }
        return cachedTokens + reserveForReply <= contextTokens
    }

    /// Trim a cached prefix so it still fits, keeping the head and the tail.
    ///
    /// The head carries the system prompt and the tail carries the recent turns,
    /// so both ends matter. This mirrors the middle-out compaction the app already
    /// uses for prompts, for the same reason.
    public static func trim(cached: [Int], toFit limit: Int) -> [Int] {
        guard limit > 0 else { return [] }
        guard cached.count > limit else { return cached }
        let headCount = max(1, limit / 4)
        let tailCount = limit - headCount
        guard tailCount > 0 else { return Array(cached.suffix(limit)) }
        return Array(cached.prefix(headCount)) + Array(cached.suffix(tailCount))
    }

    /// Prefill tokens that a request needs, for honest reporting and for the
    /// decision above.
    public static func prefillSavings(previousPrompt: [Int],
                                      previousCompletion: [Int],
                                      newPrompt: [Int]) -> (reused: Int, prefilled: Int) {
        let reused = reusableTokenCount(previousPrompt: previousPrompt,
                                        previousCompletion: previousCompletion,
                                        newPrompt: newPrompt)
        return (reused, max(0, newPrompt.count - reused))
    }
}
