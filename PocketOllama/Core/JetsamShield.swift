import Foundation

public struct MemoryBudgetResult: Sendable {
    public let isSafe: Bool
    public let errorMessage: String?
}

public final class JetsamShield: @unchecked Sendable {
    public static let shared = JetsamShield()

    /// 350 MB held back for the iOS kernel, GPU working set, and fragmentation headroom.
    let safetyMarginBytes: UInt64 = 350 * 1024 * 1024

    private init() {}

    public func validateMemoryBudget(
        modelFileSizeBytes: UInt64,
        requestedContextTokens: Int,
        kvQuant: String = "q4_0"
    ) -> MemoryBudgetResult {
        let availableRAM = MemoryScavenger.shared.purgeAndScavengeRAM()

        // No model metadata is known at this point, so size the KV cache from the device profile
        // and the requested context. GGUFHeaderParser refines this once the file is inspected.
        let hw = HardwareAutoTuner.shared.detectProfile()
        let bytesPerToken = Self.estimatedBytesPerToken(profile: hw, kvQuant: kvQuant)
        let kvCacheBytes = UInt64(Double(requestedContextTokens) * bytesPerToken)

        // totalRequired already includes the model, the KV cache and the margin,
        // so the second clause is the binding one.
        let totalRequired = modelFileSizeBytes + kvCacheBytes + safetyMarginBytes
        let isSafe = availableRAM > totalRequired

        let errorMsg: String? = isSafe ? nil :
            "Insufficient memory: model needs \(modelFileSizeBytes / (1024 * 1024)) MB plus "
            + "\(kvCacheBytes / (1024 * 1024)) MB for a \(requestedContextTokens)-token context, "
            + "but only \(availableRAM / (1024 * 1024)) MB is available. "
            + "Try a smaller model or a shorter context."

        return MemoryBudgetResult(isSafe: isSafe, errorMessage: errorMsg)
    }

    /// Planning estimate used before the model is loaded and its real dimensions
    /// are known. Delegates to the shared arithmetic so it cannot drift from the
    /// post-load check.
    private static func estimatedBytesPerToken(profile: DeviceHardwareSpec, kvQuant: String) -> Double {
        let (layers, embd, heads, kvHeads): (Int, Int, Int, Int)
        if profile.is8GBPlus {
            (layers, embd, heads, kvHeads) = (32, 4096, 32, 8)
        } else if profile.totalRAMGB >= 5.0 {
            (layers, embd, heads, kvHeads) = (28, 3072, 24, 8)
        } else {
            (layers, embd, heads, kvHeads) = (24, 1536, 12, 2)
        }
        return ModelBudget.bytesPerToken(
            layerCount: layers, embeddingLength: embd,
            headCount: heads, headCountKV: kvHeads, kvQuant: kvQuant
        )
    }
}
