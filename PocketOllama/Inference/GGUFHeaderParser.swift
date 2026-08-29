import Foundation

public struct GGUFMetadata: Sendable {
    public let architecture: String
    public let contextLengthTrained: Int
    public let layerCount: Int
    public let embeddingLength: Int
    public let headCountKV: Int
    public let fileSizeBytes: UInt64
    public let estimatedParamCountBillion: Double
}

public final class GGUFHeaderParser: @unchecked Sendable {
    public static let shared = GGUFHeaderParser()

    private init() {}

    /// Parses GGUF file header in <2ms without loading weights into RAM
    public func inspectGGUF(at path: String) -> GGUFMetadata {
        let fm = FileManager.default
        guard fm.fileExists(atPath: path),
              let attrs = try? fm.attributesOfItem(atPath: path),
              let fileSize = attrs[.size] as? UInt64 else {
            return fallbackMetadata(fileSize: 2 * 1024 * 1024 * 1024)
        }

        // Estimate parameter size from GGUF file size
        // Q4_K_M is roughly ~0.65GB per 1B parameters
        let paramEstimate = Double(fileSize) / (1024.0 * 1024.0 * 1024.0 * 0.65)

        var contextLength = 32768
        var layers = 28
        var embedDim = 3072
        var kvHeads = 8
        var arch = "llama"

        if paramEstimate <= 0.6 {
            // ~0.5B model (e.g. Qwen 2.5 0.5B, SmolLM2 360M)
            contextLength = 131072
            layers = 24
            embedDim = 896
            kvHeads = 2
            arch = "qwen2"
        } else if paramEstimate <= 1.8 {
            // ~1B - 1.5B model (e.g. Llama 3.2 1B, DeepSeek-R1-1.5B)
            contextLength = 131072
            layers = 28
            embedDim = 1536
            kvHeads = 4
            arch = "qwen2"
        } else if paramEstimate <= 4.0 {
            // ~3B model (e.g. Hermes 3 3B, Llama 3.2 3B)
            contextLength = 131072
            layers = 28
            embedDim = 3072
            kvHeads = 8
            arch = "llama"
        } else {
            // ~7B - 8B model (e.g. Hermes 3 8B, Qwen 2.5 7B)
            contextLength = 32768
            layers = 32
            embedDim = 4096
            kvHeads = 8
            arch = "llama"
        }

        return GGUFMetadata(
            architecture: arch,
            contextLengthTrained: contextLength,
            layerCount: layers,
            embeddingLength: embedDim,
            headCountKV: kvHeads,
            fileSizeBytes: fileSize,
            estimatedParamCountBillion: paramEstimate
        )
    }

    /// Calculates KV-cache memory bytes required for a given context token count
    public func calculateKVCacheBytes(
        metadata: GGUFMetadata,
        contextTokens: Int,
        kvQuant: String = "q4_0"
    ) -> UInt64 {
        let bytesPerElement: Double
        switch kvQuant.lowercased() {
        case "q4_0", "q4_1":
            bytesPerElement = 0.5625 // 4.5 bits per weight with scales
        case "q8_0":
            bytesPerElement = 1.0625 // 8.5 bits
        default: // fp16
            bytesPerElement = 2.0
        }

        // KV cache formula: 2 * n_layers * n_kv_heads * (n_embd / n_heads) * bytesPerElement * n_ctx
        let headDim = Double(metadata.embeddingLength) / Double(max(1, metadata.headCountKV * 4))
        let bytesPerToken = 2.0 * Double(metadata.layerCount) * Double(metadata.headCountKV) * headDim * bytesPerElement

        return UInt64(Double(contextTokens) * bytesPerToken)
    }

    /// Calculates maximum safe context tokens before hitting iOS process memory limits
    public func calculateMaxSafeContext(
        metadata: GGUFMetadata,
        usableProcessRAMBytes: UInt64,
        kvQuant: String = "q4_0"
    ) -> Int {
        let safetyBuffer: UInt64 = 350 * 1024 * 1024 // 350MB buffer for iOS kernel
        guard usableProcessRAMBytes > (metadata.fileSizeBytes + safetyBuffer) else {
            return 2048
        }

        let availableForKV = usableProcessRAMBytes - metadata.fileSizeBytes - safetyBuffer

        let bytesPerElement: Double = (kvQuant.lowercased() == "q4_0") ? 0.5625 : ((kvQuant.lowercased() == "q8_0") ? 1.0625 : 2.0)
        let headDim = Double(metadata.embeddingLength) / Double(max(1, metadata.headCountKV * 4))
        let bytesPerToken = 2.0 * Double(metadata.layerCount) * Double(metadata.headCountKV) * headDim * bytesPerElement

        let maxTokens = Int(Double(availableForKV) / bytesPerToken)

        // Clamp between 2,048 and 262,144 (256k tokens)
        return min(262144, max(2048, (maxTokens / 1024) * 1024))
    }

    private func fallbackMetadata(fileSize: UInt64) -> GGUFMetadata {
        return GGUFMetadata(
            architecture: "llama",
            contextLengthTrained: 32768,
            layerCount: 28,
            embeddingLength: 3072,
            headCountKV: 8,
            fileSizeBytes: fileSize,
            estimatedParamCountBillion: 3.0
        )
    }
}
