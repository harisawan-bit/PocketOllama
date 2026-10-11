// CI-only probe: verifies the llama_batch and memory-sequence API shapes.
//
// WHY THIS EXISTS
// Wiring the prefill logits fix means filling a llama_batch by hand, and
// llama.h states that llama_batch_init "leaves all members uninitialized".
// Guessing field offsets or pointer types would corrupt the KV cache silently,
// producing plausible-looking but wrong output. This makes CI prove the shapes
// instead of trusting memory.
//
// Type-checked by CI with `-target arm64-apple-ios16.4` against the real
// XCFramework headers. The binary is ios-arm64 only, so it cannot be linked on
// the x86_64 runner; type-checking is what proves every field name and Swift
// type, which is the assumption actually at risk.
//
// Wrapped in @main because Swift forbids top-level expressions in a named file.

import llama

@main
struct CIProbe {
    static func main() {
        assertBatchLayout()
        assertMemoryAPI()
        print("llama_batch layout and llama_memory_seq_* signatures verified")
    }

    /// Field by field. A wrong NAME fails to compile; a wrong TYPE is the
    /// dangerous case, because writing an Int where the API wants Int32 compiles
    /// by luck on some platforms and corrupts memory on others.
    static func assertBatchLayout() {
        var batch = llama_batch_init(8, 0, 1)
        defer { llama_batch_free(batch) }

        // Exact Swift types, asserted by assignment rather than by comment.
        let nTokens: Int32 = batch.n_tokens
        let token: UnsafeMutablePointer<llama_token>? = batch.token
        let pos: UnsafeMutablePointer<llama_pos>? = batch.pos
        let nSeqId: UnsafeMutablePointer<Int32>? = batch.n_seq_id
        let seqId: UnsafeMutablePointer<UnsafeMutablePointer<llama_seq_id>?>? = batch.seq_id

        // logits is int8_t, not Int32 and not Bool. This is the field the prefill
        // fix writes, so its width is the single most important fact here.
        let logits: UnsafeMutablePointer<Int8>? = batch.logits
        if let p = logits {
            p[0] = 1
            p[1] = 0
        }

        // Every field must be writable, not just readable. A const-correct API
        // change that broke the planned fix would fail here.
        batch.n_tokens = nTokens
        batch.token = token
        batch.pos = pos
        batch.n_seq_id = nSeqId
        batch.seq_id = seqId
        batch.logits = logits

        print("  n_tokens : Int32")
        print("  token    : UnsafeMutablePointer<llama_token>?")
        print("  pos      : UnsafeMutablePointer<llama_pos>?")
        print("  n_seq_id : UnsafeMutablePointer<Int32>?")
        print("  seq_id   : UnsafeMutablePointer<UnsafeMutablePointer<llama_seq_id>?>?")
        print("  logits   : UnsafeMutablePointer<Int8>?")
    }

    /// The memory-sequence API the prefix cache depends on. Pinning exact
    /// signatures means a future llama.cpp bump that changes one fails here
    /// rather than in a corrupted prompt on a device.
    static func assertMemoryAPI() {
        let rm: (llama_memory_t, llama_seq_id, llama_pos, llama_pos) -> Bool = llama_memory_seq_rm
        let cp: (llama_memory_t, llama_seq_id, llama_seq_id, llama_pos, llama_pos) -> Void = llama_memory_seq_cp
        // llama_memory_seq_keep takes TWO arguments, not four. An earlier draft of
        // this probe asserted a four-argument shape copied from seq_rm, and the
        // real build rejected it. PrefixCache.swift documents seq_keep as taking a
        // position range, which is wrong for this llama.cpp version and is
        // corrected here.
        let keep: (llama_memory_t, llama_seq_id) -> Void = llama_memory_seq_keep
        let clear: (llama_memory_t, Bool) -> Void = llama_memory_clear
        _ = (rm, cp, keep, clear)
        print("  llama_memory_seq_rm   verified")
        print("  llama_memory_seq_cp   verified")
        print("  llama_memory_seq_keep verified")
        print("  llama_memory_clear    verified")
    }
}
