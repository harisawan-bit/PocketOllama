// CI-only probe: prints the real llama_batch layout on the macOS runner.
//
// WHY THIS EXISTS
// Wiring the prefill logits fix means filling a llama_batch by hand, and
// llama.h states that llama_batch_init "leaves all members uninitialized".
// Guessing field offsets or getting the pointer types wrong would corrupt the KV
// cache silently. This probe makes the CI runner tell us the truth instead.
//
// It links the same XCFramework the app links, so what it prints is what the app
// will see.

import llama

// Field-by-field assertions. If any of these fails to compile, the assumptions in
// PrefillPlan and the planned decode-loop change are wrong, and CI stops here
// rather than shipping a corrupted prompt.

func assertBatchLayout() {
    var batch = llama_batch_init(8, 0, 1)
    defer { llama_batch_free(batch) }

    // The five fields llama_batch_get_one hands back as null pointers, and which
    // must therefore be written by hand when using llama_batch_init.
    batch.n_tokens = 0
    withUnsafeMutablePointer(to: &batch.token) { _ = $0 }
    withUnsafeMutablePointer(to: &batch.pos) { _ = $0 }
    withUnsafeMutablePointer(to: &batch.n_seq_id) { _ = $0 }
    withUnsafeMutablePointer(to: &batch.seq_id) { _ = $0 }
    withUnsafeMutablePointer(to: &batch.logits) { _ = $0 }

    // Types matter as much as names: writing an Int where the API wants Int32
    // compiles only by luck on some platforms and corrupts memory on others.
    let _: Int32 = batch.n_tokens
    let _: UnsafeMutablePointer<llama_token>? = batch.token
    let _: UnsafeMutablePointer<llama_pos>? = batch.pos
    let _: UnsafeMutablePointer<Int32>? = batch.n_seq_id
    let _: UnsafeMutablePointer<UnsafeMutablePointer<llama_seq_id>?>? = batch.seq_id
    let _: UnsafeMutablePointer<Int8>? = batch.logits

    // logits is int8_t, not Int32 or Bool. That is the field the fix writes.
    let logitsPtr: UnsafeMutablePointer<Int8>? = batch.logits
    if let p = logitsPtr {
        p[0] = 1
        p[1] = 0
    }

    print("llama_batch layout verified")
    print("  n_tokens : Int32")
    print("  token    : UnsafeMutablePointer<llama_token>?")
    print("  pos      : UnsafeMutablePointer<llama_pos>?")
    print("  n_seq_id : UnsafeMutablePointer<Int32>?")
    print("  seq_id   : UnsafeMutablePointer<UnsafeMutablePointer<llama_seq_id>?>?")
    print("  logits   : UnsafeMutablePointer<Int8>?")
}

// Confirm the memory-sequence API the prefix cache needs really is exported with
// the signatures the plan assumes.
func assertMemoryAPI() {
    let _: (llama_memory_t, llama_seq_id, llama_pos, llama_pos) -> Bool = llama_memory_seq_rm
    let _: (llama_memory_t, llama_seq_id, llama_seq_id, llama_pos, llama_pos) -> Void = llama_memory_seq_cp
    let _: (llama_memory_t, llama_seq_id, llama_pos, llama_pos) -> Void = llama_memory_seq_keep
    let _: (llama_memory_t, Bool) -> Void = llama_memory_clear
    print("llama_memory_seq_* signatures verified")
}

assertBatchLayout()
assertMemoryAPI()
