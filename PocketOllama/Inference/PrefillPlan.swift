import Foundation

/// Prefill chunk planning: which chunks need logits, and where.
///
/// The defect this addresses, verified in the llama.cpp source rather than
/// assumed. `llama_batch_get_one` passes `logits = nullptr`, and
/// `src/llama-batch.cpp:1308-1311` then defaults to:
///
///     // if no logits array is given, default to only the last token being an output
///     t.output = batch_inp.logits ? (batch_inp.logits[i] != 0)
///                                 : (i == batch_inp.n_tokens - 1);
///
/// So with a null logits array, EVERY prefill chunk marks its last token as an
/// output. Each chunk therefore runs the full `n_vocab` output projection for one
/// token and copies `n_vocab` floats from the Metal device to the CPU, then throws
/// it away, because only the final chunk's output is ever read. An 8192-token
/// prompt prefilled in 512-token chunks wastes 15 projections and 15 copies.
///
/// The copy is confirmed reachable, not theoretical: `needs_raw_logits()` at
/// `llama-context.cpp:1688` returns true whenever a sequence has no *backend*
/// sampler, and this app samples on CPU through `llama_sampler_*`.
///
/// This file holds only the arithmetic. It is dependency-free so the CI self-check
/// compiles THIS file and exercises the off-by-one cases, rather than a copy that
/// could drift from the loop that consumes it.
public enum PrefillPlan {

    /// One prefill chunk.
    public struct Chunk: Equatable, Sendable {
        /// Zero-based index of this chunk in the prompt.
        public let index: Int
        /// First token index in the prompt, for slicing.
        public let start: Int
        /// Number of tokens in this chunk.
        public let length: Int
        /// Whether the final token of this chunk must produce logits.
        ///
        /// True for exactly one chunk: the last one. Every other chunk would waste
        /// an `n_vocab` projection and a device-to-host copy.
        public let needsLogits: Bool

        public init(index: Int, start: Int, length: Int, needsLogits: Bool) {
            self.index = index
            self.start = start
            self.length = length
            self.needsLogits = needsLogits
        }
    }

    /// Split a prompt into prefill chunks of at most `ubatch` tokens.
    ///
    /// - Parameters:
    ///   - totalTokens: prompt length in tokens
    ///   - ubatch: physical batch size, i.e. `n_ubatch`. Must be positive.
    ///
    /// An empty prompt produces no chunks at all. That matters: returning a single
    /// zero-length chunk would ask the engine to decode nothing and then read
    /// logits that were never produced.
    public static func plan(totalTokens: Int, ubatch: Int) -> [Chunk] {
        guard totalTokens > 0, ubatch > 0 else { return [] }

        var chunks = [Chunk]()
        var start = 0
        var index = 0
        while start < totalTokens {
            let length = min(ubatch, totalTokens - start)
            chunks.append(Chunk(index: index, start: start, length: length, needsLogits: false))
            start += length
            index += 1
        }

        // Mark only the final chunk. Done after the loop so a prompt that divides
        // exactly still flags a full final chunk, which is the easy off-by-one.
        if !chunks.isEmpty {
            let last = chunks.count - 1
            chunks[last] = Chunk(index: chunks[last].index,
                                 start: chunks[last].start,
                                 length: chunks[last].length,
                                 needsLogits: true)
        }
        return chunks
    }

    /// How many chunks request logits. Always 0 or 1.
    ///
    /// Exposed because "exactly one" is the invariant the whole optimisation
    /// rests on. If this ever returns more than 1 the change has regressed to the
    /// behaviour it was meant to remove.
    public static func logitsRequestCount(_ chunks: [Chunk]) -> Int {
        chunks.filter { $0.needsLogits }.count
    }

    /// Number of output projections and device-to-host copies avoided.
    public static func wastedWorkAvoided(totalTokens: Int, ubatch: Int) -> Int {
        max(0, plan(totalTokens: totalTokens, ubatch: ubatch).count - 1)
    }

    /// Index of the final token within a chunk that needs logits, or nil.
    ///
    /// Used to set `batch.logits[i] = 1` at exactly one position. The index is
    /// `length - 1`, and a zero-length chunk must never be asked, because index
    /// -1 would write outside the array.
    public static func logitsIndex(in chunk: Chunk) -> Int? {
        guard chunk.needsLogits, chunk.length > 0 else { return nil }
        return chunk.length - 1
    }

    /// Total tokens covered by a plan. Must equal the prompt length.
    ///
    /// A cheap invariant for tests and for a debug assertion in the loop: if the
    /// chunks do not add up, the prompt is being silently truncated or repeated.
    public static func totalTokens(in chunks: [Chunk]) -> Int {
        chunks.reduce(0) { $0 + $1.length }
    }
}
