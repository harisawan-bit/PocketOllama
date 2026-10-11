import Foundation

/// RAM bands for devices not present in the device table.
///
/// Bands, not a single threshold. The old fallback had one 7.2 GB cut-off, so a
/// 2 GB phone and a 6 GB phone were both handed the same 3B recommendation and
/// the same 8192-token context. Dependency-free so CI can test the boundaries.
public enum RAMBands {
    public struct Band {
        public let context: Int
        public let kv: String
        public let tier: String
    }

    public static func band(totalRAMGB: Double) -> Band {
        switch totalRAMGB {
        // Under 3 GB: the A11 iPhone 8 and the A12 XR. 2k is all the KV cache a
        // 0.5B model has room for after the weights are mapped.
        case 0..<3.0:     return Band(context: 2048, kv: "q8_0", tier: "Qwen 2.5 0.5B")
        // 3 to 4.5 GB: the XR, the 11, the SE 2 and the 12 mini. A 1.5B at 4k.
        case 3.0..<4.5:   return Band(context: 4096, kv: "q8_0", tier: "Qwen 2.5 1.5B / Llama 3.2 3B")
        // 4.5 to 6.5 GB: the 12, 12 Pro, 13 and 13 Pro. 8k with a 3B.
        case 4.5..<6.5:   return Band(context: 8192, kv: "q8_0", tier: "Llama 3.2 3B / Qwen 2.5 3B")
        // 6.5 to under 8 GB: the A16 phones at 6 GB. This band used to jump to
        // 32k and the 8B tier, which a 6 GB device cannot hold: 4.9 GB of weights
        // leaves no room for a 32k cache. 16k with a 3B is what fits.
        case 6.5..<8.0:   return Band(context: 16384, kv: "q4_0", tier: "Hermes 3 3B / Llama 3.2 3B")
        default:          return Band(context: 32768, kv: "q4_0", tier: "Hermes 3 8B / DeepSeek-R1")
        }
    }
}

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
        // One shared rule with the slider, so the range offered and the value
        // produced cannot drift. The floor is 512 because the budget legitimately
        // returns less than 1024 on the tightest devices, and flooring those to 0
        // left no usable context at all.
        return ContextSizing.floorContext(capped)
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
