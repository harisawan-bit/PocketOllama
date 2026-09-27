import Foundation

/// KV-cache arithmetic and context limits, in one dependency-free place.
///
/// This logic was previously duplicated across GGUFHeaderParser (twice) and
/// JetsamShield, with the copies free to disagree about head_dim. Centralising it
/// also makes it testable: the CI self-check compiles this file directly.
public enum ModelBudget {
    /// Bytes per weight for a quantised K/V cache.
    public static func bytesPerElement(kvQuant: String) -> Double {
        switch kvQuant.lowercased() {
        case "q4_0", "q4_1": return 0.5625   // 4.5 bits plus scales
        case "q8_0":        return 1.0625   // 8.5 bits
        default:            return 2.0      // f16
        }
    }

    /// Bytes of K/V cache one token occupies.
    ///
    /// head_dim is n_embd / n_head, NOT n_embd / n_head_kv. Under grouped-query
    /// attention the latter overstates the cache by the GQA factor, which made the
    /// safe-context estimate far too small on Llama-3-class models.
    public static func bytesPerToken(
        layerCount: Int,
        embeddingLength: Int,
        headCount: Int,
        headCountKV: Int,
        kvQuant: String
    ) -> Double {
        let kvHeads = Double(max(1, headCountKV))
        let headDim = Double(embeddingLength) / Double(max(1, headCount))
        return 2.0 * Double(max(1, layerCount)) * kvHeads * headDim * bytesPerElement(kvQuant: kvQuant)
    }

    public static func kvCacheBytes(
        metadata: GGUFBudgetFields,
        contextTokens: Int,
        kvQuant: String
    ) -> UInt64 {
        let perToken = bytesPerToken(
            layerCount: metadata.layerCount,
            embeddingLength: metadata.embeddingLength,
            headCount: metadata.headCount,
            headCountKV: metadata.headCountKV,
            kvQuant: kvQuant
        )
        return UInt64(Double(max(0, contextTokens)) * perToken)
    }

    /// The largest context that both fits in memory and stays inside what the
    /// model was trained for.
    ///
    /// Ignoring the trained length was a real defect: a model trained at 8k was
    /// handed up to 64k, which both wastes KV memory and degrades output past
    /// the point the model was trained to handle.
    public static func safeContextTokens(
        metadata: GGUFBudgetFields,
        usableProcessRAMBytes: UInt64,
        safetyBufferBytes: UInt64,
        kvQuant: String
    ) -> Int {
        let floorTokens = 2048
        guard usableProcessRAMBytes > metadata.fileSizeBytes + safetyBufferBytes else {
            return min(floorTokens, max(1, metadata.contextLengthTrained))
        }

        let availableForKV = usableProcessRAMBytes - metadata.fileSizeBytes - safetyBufferBytes
        let perToken = bytesPerToken(
            layerCount: metadata.layerCount,
            embeddingLength: metadata.embeddingLength,
            headCount: metadata.headCount,
            headCountKV: metadata.headCountKV,
            kvQuant: kvQuant
        )
        guard perToken > 0 else { return floorTokens }

        let memoryLimit = Int(Double(availableForKV) / perToken)
        // Never exceed the trained context: beyond it the model degrades and the
        // extra KV memory buys nothing.
        let trained = max(1, metadata.contextLengthTrained)
        let capped = min(memoryLimit, trained)
        return min(262144, max(1, (capped / 1024) * 1024 == 0 ? capped : (capped / 1024) * 1024))
    }

    /// Recommend a KV quantisation for this model on this device: quality where
    /// there is room, memory where there is not.
    public static func recommendKVQuant(
        metadata: GGUFBudgetFields,
        desiredContext: Int,
        usableProcessRAMBytes: UInt64,
        safetyBufferBytes: UInt64
    ) -> String {
        let free = usableProcessRAMBytes > metadata.fileSizeBytes + safetyBufferBytes
            ? usableProcessRAMBytes - metadata.fileSizeBytes - safetyBufferBytes
            : 0
        for candidate in ["q8_0", "q4_0"] {
            let need = kvCacheBytes(metadata: metadata, contextTokens: desiredContext, kvQuant: candidate)
            if UInt64(need) < free { return candidate }
        }
        return "q4_0"
    }
}

/// The subset of GGUF metadata the budget maths needs.
public protocol GGUFBudgetFields {
    var contextLengthTrained: Int { get }
    var layerCount: Int { get }
    var embeddingLength: Int { get }
    var headCount: Int { get }
    var headCountKV: Int { get }
    var fileSizeBytes: UInt64 { get }
}
