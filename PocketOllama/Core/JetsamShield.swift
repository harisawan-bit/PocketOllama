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

    private let safetyMarginBytes: UInt64 = 350 * 1024 * 1024

    private init() {}

    public func validateMemoryBudget(
        modelFileSizeBytes: UInt64,
        requestedContextTokens: Int,
        kvQuant: String = "q4_0"
    ) -> MemoryBudgetResult {
        let availableRAM = MemoryScavenger.shared.purgeAndScavengeRAM()

        let bytesPerToken: Double = (kvQuant == "q4_0") ? 512.0 : 1024.0
        let kvCacheBytes = UInt64(Double(requestedContextTokens) * bytesPerToken * 32.0)

        let totalRequired = modelFileSizeBytes + kvCacheBytes + safetyMarginBytes
        let isSafe = availableRAM > totalRequired

        let availableForKV = (availableRAM > (modelFileSizeBytes + safetyMarginBytes)) ? (availableRAM - modelFileSizeBytes - safetyMarginBytes) : 0
        let maxSafeTokens = Int(Double(availableForKV) / (bytesPerToken * 32.0))

        let errorMsg: String? = isSafe ? nil : "Insufficient memory: Required \(totalRequired / (1024*1024))MB, Available \(availableRAM / (1024*1024))MB."

        return MemoryBudgetResult(
            isSafe: isSafe,
            availableRAMBytes: availableRAM,
            requiredRAMBytes: totalRequired,
            safeMaxContextTokens: max(1024, maxSafeTokens),
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

        let compacted = "\(prefix)\n\n[... Warning: Context compacted by Middle-Out Shield ...]\n\n\(suffix)"
        return (compacted, true)
    }
}
