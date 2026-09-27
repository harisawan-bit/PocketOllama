import Foundation

/// Context sizing maths, kept dependency-free so the CI self-check can compile
/// THIS file and catch load-fatal mistakes before they reach a phone.
public enum ContextSizing {
    /// llama.cpp requires n_ubatch <= n_batch. Violating it makes
    /// llama_init_from_model fail, so a model simply will not load.
    public static func batchSizes(prefillBatch requested: Int) -> (batch: Int, ubatch: Int) {
        let r = max(32, requested)
        let batch = max(r, 512)
        let ubatch = min(batch, max(512, min(r * 2, 2048)))
        return (batch, ubatch)
    }

    /// Threads actually used: the configured value capped by the thermal governor.
    public static func effectiveThreads(configured: Int, thermalCap: Int) -> Int {
        max(1, min(configured, max(1, thermalCap)))
    }
}
