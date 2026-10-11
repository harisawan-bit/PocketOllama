import Foundation

/// n-gram lookup drafting, ported from llama.cpp's `common/ngram-cache.cpp` at the
/// pinned b11218 and verified line by line against that source.
///
/// WHY THIS MATTERS FOR A PHONE
/// The draft-model approach needs a second model resident, which the RAM gate in
/// `SpeculativeDecoding` correctly refuses on small devices. This needs **no second
/// model at all**: it drafts by finding token sequences that already appeared in
/// the current generation and repeating them.
///
/// That makes it the right default for iOS. It costs no extra memory, so it works
/// on a 2 GB device where a draft model cannot fit.
///
/// It is most effective exactly where a phone is weakest: long repetitive output.
/// Code, lists, boilerplate, and a reasoning model restating its own thinking all
/// contain the repeats this exploits. The doc's own example is refactoring source
/// code.
///
/// Upstream reports acceptance around 0.58 in mixed use and up to 0.70 with the
/// hash variant, so it is not universal. When there is no repetition it simply
/// drafts nothing and costs one failed hash lookup per token.
public enum NGramDrafting {

    /// Upstream's bounds, from `LLAMA_NGRAM_MIN` / `LLAMA_NGRAM_MAX`.
    public static let ngramMin = 1
    public static let ngramMax = 4

    /// `LLAMA_NGRAM_STATIC`: the fixed key size used against an external corpus.
    /// We ship no corpus, so the static path is always empty, which is equivalent
    /// to upstream running without `--lookup-cache-static`.
    public static let ngramStatic = 2

    /// Minimum context before any drafting is attempted. Upstream returns early
    /// below this, because a 2-gram key needs at least 2 tokens of history.
    public static let minimumContextTokens = ngramStatic

    /// Per-n-gram-size thresholds, indexed by `size - 1`.
    ///
    /// These are upstream's numbers exactly, read off `ngram-cache.cpp`:
    ///
    ///     draft_min_sample_size_lax[NG_MAX] = { 2, 3, 3, 4 }
    ///     draft_min_percent_lax[NG_MAX]     = {66, 50, 50, 50}
    ///
    /// The two tables are different quantities and must not be conflated: sample
    /// size is a small COUNT of observations, percent is a share. An earlier draft
    /// of this port used {66,50,50,50} for both, which demanded 50 sightings of a
    /// 1-gram before drafting anything, so it never drafted at all.
    ///
    /// The "lax" pair is used for the context cache, where the evidence is the
    /// current generation and therefore directly relevant. The "strict" pair is
    /// for the cross-session cache, where a wrong draft costs more.
    public static let minSampleSizeLax    = [2, 3, 3, 4]
    public static let minPercentLax       = [66, 50, 50, 50]
    public static let minSampleSizeStrict = [4, 3, 2, 2]
    public static let minPercentStrict    = [75, 66, 66, 66]

    /// Counts of what followed each n-gram, within one generation.
    public typealias Counts = [Int: Int]

    /// A read-only view of one cache. Key is the n-gram, value is the observed
    /// follower counts.
    public struct Cache {
        private var storage: [NGramKey: Counts]

        public init() { storage = [:] }

        /// How many distinct n-grams are tracked. Useful for tests and for
        /// reporting memory use honestly.
        public var count: Int { storage.count }

        public subscript(key: NGramKey) -> Counts? {
            storage[key]
        }

        fileprivate mutating func record(_ key: NGramKey, follower: Int) {
            storage[key, default: [:]][follower, default: 0] += 1
        }
    }

    /// An n-gram of up to `ngramMax` tokens, padded so equal-length comparison
    /// works. Padding with a sentinel that cannot be a real token keeps two
    /// different-length n-grams from colliding.
    public struct NGramKey: Hashable, Sendable {
        public let tokens: [Int]

        public init(_ tokens: [Int]) {
            precondition(tokens.count <= NGramDrafting.ngramMax,
                         "n-gram longer than the supported maximum")
            self.tokens = tokens
        }

        public static func == (lhs: NGramKey, rhs: NGramKey) -> Bool {
            lhs.tokens == rhs.tokens
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(tokens)
        }
    }

    /// Build the key for a given size ending at `end`, reading from the generated
    /// tokens plus any tokens already drafted this round.
    ///
    /// This mirrors upstream's `get_token(inp, draft, j)`: positions before the end
    /// of the real generation come from the prompt, positions after it come from
    /// the draft built so far. Getting that wrong is what makes a naive port fail
    /// on the second drafted token.
    public static func key(size: Int,
                           generated: [Int],
                           drafted: [Int],
                           generatedEnd: Int) -> NGramKey? {
        guard size >= 1, size <= ngramMax else { return nil }
        var tokens = [Int]()
        tokens.reserveCapacity(size)
        // The absolute index of the last token belonging to the key.
        let last = generatedEnd + drafted.count - 1
        for j in (last - size + 1)...last {
            if j < generatedEnd {
                let idx = generated.count - (generatedEnd - j)
                guard idx >= 0, idx < generated.count else { return nil }
                tokens.append(generated[idx])
            } else {
                let d = j - generatedEnd
                guard d >= 0, d < drafted.count else { return nil }
                tokens.append(drafted[d])
            }
        }
        return NGramKey(tokens)
    }

    /// Record every n-gram of every supported size that ends inside `newTokens`.
    ///
    /// Upstream's contract is that the token sequence is only ever APPENDED to; a
    /// change in the middle requires a full rebuild. Honouring that here keeps the
    /// counts meaningful.
    public static func update(_ cache: inout Cache,
                              generated: [Int],
                              newTokenCount: Int) {
        guard newTokenCount > 0 else { return }
        let end = generated.count
        let start = end - newTokenCount
        guard start >= 0 else { return }

        for position in start..<end {
            for size in ngramMin...ngramMax {
                let first = position - size + 1
                guard first >= 0 else { continue }
                // The follower is the token immediately after the n-gram.
                guard position + 1 < end else { continue }
                let keyTokens = Array(generated[first...position])
                let follower = generated[position + 1]
                cache.record(NGramKey(keyTokens), follower: follower)
            }
        }
    }

    /// The single best-scoring follower for a key, or nil.
    ///
    /// Scoring is the product of the primary count and the static count. With no
    /// static corpus the static count is the upstream default of 1 for an unknown
    /// token, so the product degenerates to the primary count. That is the correct
    /// behaviour, not a simplification: upstream does exactly this when
    /// `--lookup-cache-static` is absent.
    public static func bestFollower(_ counts: Counts?) -> (token: Int, count: Int, total: Int)? {
        guard let counts, !counts.isEmpty else { return nil }
        var bestToken = 0
        var bestCount = 0
        var total = 0
        for (token, count) in counts {
            if count > bestCount {
                bestToken = token
                bestCount = count
            }
            total += count
        }
        guard bestCount > 0, total > 0 else { return nil }
        return (bestToken, bestCount, total)
    }

    /// Upstream's acceptance test: enough samples, and the winner is a large
    /// enough share of them.
    ///
    /// Both conditions matter. The sample-size floor stops a single coincidence
    /// from being treated as a pattern. The percentage floor stops drafting when
    /// the history is genuinely split between several continuations, because a
    /// coin-flip draft wastes the whole verification pass.
    public static func passesThreshold(count: Int, total: Int, minSampleSize: Int, minPercent: Int) -> Bool {
        guard total > 0, count > 0 else { return false }
        if total < minSampleSize { return false }
        // Integer arithmetic, exactly as upstream: 100 * max < min_percent * sum.
        if 100 * count < minPercent * total { return false }
        return true
    }

    /// Draft up to `maxDraft` tokens from the context cache.
    ///
    /// Tries the longest n-gram first, because a longer match is stronger
    /// evidence. Stops at the first token it cannot justify, since a draft is
    /// verified left to right and a wrong prefix discards everything after it.
    public static func draft(generated: [Int],
                             alreadyDrafted: [Int],
                             cache: Cache,
                             maxDraft: Int) -> [Int] {
        guard maxDraft > 0 else { return [] }
        guard generated.count + alreadyDrafted.count >= minimumContextTokens else { return [] }

        var drafted = alreadyDrafted
        // The loop bound is the total draft length, not the number appended.
        while drafted.count < maxDraft {
            var chosen: Int? = nil

            // Longest key first.
            for size in stride(from: ngramMax, through: ngramMin, by: -1) {
                let absoluteEnd = generated.count + drafted.count - 1
                guard absoluteEnd - size + 1 >= 0 else { continue }
                guard let key = key(size: size, generated: generated,
                                    drafted: drafted, generatedEnd: generated.count) else { continue }
                guard let best = bestFollower(cache[key]) else { continue }
                // Index by n-gram size, matching upstream's 1-based use.
                let idx = size - 1
                guard idx >= 0, idx < minSampleSizeLax.count else { continue }
                if passesThreshold(count: best.count, total: best.total,
                                   minSampleSize: minSampleSizeLax[idx],
                                   minPercent: minPercentLax[idx]) {
                    chosen = best.token
                    break
                }
            }

            guard let token = chosen else { break }
            drafted.append(token)
        }
        return drafted
    }

    /// Expected tokens per verification pass, given how often a draft is right.
    ///
    /// Same closed form as the draft-model case: with acceptance rate `a` and `k`
    /// drafts, expected accepted drafts is `(1 - a^(k+1)) / (1 - a)`, plus one for
    /// the round's own forward pass.
    public static func expectedTokensPerPass(acceptanceRate a: Float, draftsPerRound k: Int) -> Float {
        guard k > 0 else { return 1 }
        guard a < 1 else { return Float(k) + 1 }
        guard a > 0 else { return 1 }
        let fk = Float(k)
        return (1 - pow(a, fk + 1)) / (1 - a) + 1
    }

    /// Whether n-gram drafting is worth its overhead on this device.
    ///
    /// Always true on memory grounds, because it allocates nothing beyond the
    /// counts. It is gated only on having enough context for a key to exist, which
    /// is a correctness requirement rather than a heuristic.
    public static func isWorthwhile(contextTokens: Int) -> Bool {
        contextTokens >= minimumContextTokens
    }
}
