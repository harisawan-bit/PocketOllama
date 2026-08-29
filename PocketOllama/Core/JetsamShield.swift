import Foundation

public struct MemoryBudgetResult: Sendable {
    public let isSafe: Bool
    public let availableRAMBytes: UInt64
    public let requiredRAMBytes: UInt64
    public let safeMaxContextTokens: Int
    public let suggestedKVQuant: String
    public let errorMessage: String?
}

public final class JetsamShield: @unchecked Sendable {
    public static let shared = JetsamShield()

    private let safetyMarginBytes: UInt64 = 300 * 1024 * 1024 // 300MB buffer for iOS kernel

    private init() {}

    public func validateMemoryBudget(
        modelFileSizeBytes: UInt64,
        requestedContextTokens: Int,
        kvQuant: String = "q4_0"
    ) -> MemoryBudgetResult {
        let availableRAM = MemoryScavenger.shared.purgeAndScavengeRAM()

        // Real KV cache calculation per token:
        // For ~3B model: 28 layers * 8 kv heads * 128 head dim * 0.5625 (Q4_0) * 2 (K+V) = ~32 KB per token
        // For ~8B model: 32 layers * 8 kv heads * 128 head dim * 0.5625 (Q4_0) * 2 (K+V) = ~36 KB per token
        let bytesPerToken: Double = (kvQuant.lowercased() == "q4_0") ? 36864.0 : 73728.0
        let kvCacheBytes = UInt64(Double(requestedContextTokens) * bytesPerToken)

        let totalRequired = modelFileSizeBytes + kvCacheBytes + safetyMarginBytes
        let isSafe = availableRAM > (modelFileSizeBytes + safetyMarginBytes)

        let availableForKV = (availableRAM > (modelFileSizeBytes + safetyMarginBytes)) ? (availableRAM - modelFileSizeBytes - safetyMarginBytes) : 0
        let maxSafeTokens = Int(Double(availableForKV) / bytesPerToken)

        let errorMsg: String? = isSafe ? nil : "Insufficient memory: Model requires \(modelFileSizeBytes / (1024*1024))MB, but only \(availableRAM / (1024*1024))MB available."

        return MemoryBudgetResult(
            isSafe: isSafe,
            availableRAMBytes: availableRAM,
            requiredRAMBytes: totalRequired,
            safeMaxContextTokens: max(2048, (maxSafeTokens / 1024) * 1024),
            suggestedKVQuant: (availableRAM < 4 * 1024 * 1024 * 1024) ? "q4_0" : "q8_0",
            errorMessage: errorMsg
        )
    }

    public func compactPromptMiddleOut(prompt: String, maxAllowedTokens: Int) -> (compactedPrompt: String, wasCompacted: Bool) {
        let maxChars = maxAllowedTokens * 4
        if prompt.count <= maxChars {
            return (prompt, false)
        }

        let prefixLength = Int(Double(maxChars) * 0.25)
        let suffixLength = Int(Double(maxChars) * 0.70)

        let prefixIndex = prompt.index(prompt.startIndex, offsetBy: min(prefixLength, prompt.count))
        let suffixIndex = prompt.index(prompt.endIndex, offsetBy: -min(suffixLength, prompt.count))

        let prefix = String(prompt[..<prefixIndex])
        let suffix = String(prompt[suffixIndex...])

        let compacted = "\(prefix)\n\n[... Context compacted by Middle-Out Shield ...]\n\n\(suffix)"
        return (compacted, true)
    }
}
