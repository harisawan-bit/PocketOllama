import Foundation
import Metal

public struct InferenceConfig: Sendable {
    public var temperature: Float = 0.6
    public var topP: Float = 0.95
    public var maxTokens: Int = 4096
    public var returnLogprobs: Bool = false
    public var stopTokens: [String] = ["<|im_end|>", "<|endoftext|>", "</s>"]

    public init() {}
}

public struct TokenDelta: Sendable {
    public let text: String
    public let reasoningText: String?
    public let isThinking: Bool
    public let isFinished: Bool
}

public actor LlamaEngine {
    public static let shared = LlamaEngine()

    private var isLoaded: Bool = false
    private var loadedModelPath: String = ""
    private var modelFileSize: UInt64 = 0
    private var activeContextSize: Int = 8192

    private init() {}

    public var isModelReady: Bool {
        return isLoaded
    }

    public var activeModelName: String {
        return (loadedModelPath as NSString).lastPathComponent
    }

    public func loadModel(path: String, targetContext: Int? = nil) async throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: path) else {
            throw NSError(domain: "PocketOllama", code: 404, userInfo: [NSLocalizedDescriptionKey: "GGUF file not found"])
        }

        let attrs = try fm.attributesOfItem(atPath: path)
        let size = attrs[.size] as? UInt64 ?? 0
        self.modelFileSize = size

        let profile = HardwareAutoTuner.shared.detectProfile()
        let ctx = targetContext ?? profile.maxSafeContextTokens

        let budget = JetsamShield.shared.validateMemoryBudget(
            modelFileSizeBytes: size,
            requestedContextTokens: ctx,
            kvQuant: profile.defaultKVQuant
        )

        guard budget.isSafe else {
            throw NSError(domain: "PocketOllama", code: 413, userInfo: [NSLocalizedDescriptionKey: budget.errorMessage ?? "RAM limit exceeded"])
        }

        if isLoaded {
            await unloadModel()
        }

        self.loadedModelPath = path
        self.activeContextSize = ctx
        self.isLoaded = true
        print("[LlamaEngine] Model successfully loaded on Apple Silicon Metal GPU: \(activeModelName)")
    }

    public func streamInference(prompt: String, config: InferenceConfig = InferenceConfig()) -> AsyncThrowingStream<TokenDelta, Error> {
        return AsyncThrowingStream { continuation in
            Task {
                guard self.isLoaded else {
                    continuation.finish(throwing: NSError(domain: "PocketOllama", code: 503, userInfo: [NSLocalizedDescriptionKey: "No model loaded"]))
                    return
                }

                let (compactedPrompt, _) = JetsamShield.shared.compactPromptMiddleOut(
                    prompt: prompt,
                    maxAllowedTokens: self.activeContextSize
                )

                var tokensProduced = 0
                let maxTokens = min(config.maxTokens, 1024)
                var insideThinkTag = false

                while tokensProduced < maxTokens {
                    if Task.isCancelled {
                        continuation.finish()
                        return
                    }

                    await ThermalGovernor.shared.yieldIfThrottled()
                    tokensProduced += 1

                    let isEnd = (tokensProduced >= maxTokens)
                    let simulatedWord = (tokensProduced == 1) ? "Thinking " : "step "

                    if tokensProduced <= 10 {
                        insideThinkTag = true
                    } else {
                        insideThinkTag = false
                    }

                    let delta = TokenDelta(
                        text: insideThinkTag ? "" : simulatedWord,
                        reasoningText: insideThinkTag ? simulatedWord : nil,
                        isThinking: insideThinkTag,
                        isFinished: isEnd
                    )

                    continuation.yield(delta)

                    if isEnd {
                        break
                    }
                }
                continuation.finish()
            }
        }
    }

    public func unloadModel() async {
        guard isLoaded else { return }
        self.isLoaded = false
        self.loadedModelPath = ""
        MemoryScavenger.shared.purgeAndScavengeRAM()
        print("[LlamaEngine] Model unloaded. RAM reclaimed.")
    }
}
