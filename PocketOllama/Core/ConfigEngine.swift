import Foundation
import Combine
import llama

public enum SamplingPreset: String, CaseIterable, Identifiable {
    case reasoning = "Reasoning / DeepSeek"
    case coding = "Coding & Agents"
    case creative = "Creative & Chat"
    case eval = "Deterministic Eval"

    public var id: String { rawValue }
}

public enum ThermalProfile: String, CaseIterable, Identifiable {
    case performance = "Max Performance"
    case balanced = "Balanced (Overnight)"
    case cool = "Silent & Cool"

    public var id: String { rawValue }
}

public final class ConfigEngine: ObservableObject, @unchecked Sendable {
    public static let shared = ConfigEngine()

    // MARK: - User-Adjustable Settings (with Defaults)
    @Published public var contextWindowTokens: Int = 16384
    @Published public var kvQuantization: String = "q4_0"
    @Published public var threadCount: Int = 4
    @Published public var prefillBatchSize: Int = 256
    @Published public var thermalProfile: ThermalProfile = .balanced
    
    // Sampling Parameters
    @Published public var selectedPreset: SamplingPreset = .reasoning
    @Published public var temperature: Float = 0.6
    @Published public var topP: Float = 0.95
    @Published public var minP: Float = 0.05
    @Published public var topK: Int32 = 40
    @Published public var reasoningBudgetTokens: Int = 8192

    // Memory Controls
    @Published public var enableMemoryLock: Bool = true
    @Published public var enableDarwinBalloonPurge: Bool = true

    // Server Controls
    @Published public var serverPort: UInt16 = 11434
    @Published public var serverHostname: String = "iphone-ai"

    // MARK: - Dynamic Recommendations (Computed per model & hardware)
    @Published public private(set) var recommendedContextTokens: Int = 16384
    @Published public private(set) var maxSafeContextTokens: Int = 32768
    @Published public private(set) var recommendedKVQuant: String = "q4_0"
    @Published public private(set) var recommendedThreads: Int = 4
    @Published public private(set) var estimatedKVRAMMB: Double = 0.0

    private var cancellables = Set<AnyCancellable>()
    private var lastKnownMetadata: GGUFMetadata?
    /// True once the user moves the context control, so a model download stops
    /// overriding it.
    public var userHasChosenContext = false

    private init() {
        let hw = HardwareAutoTuner.shared.detectProfile()
        self.threadCount = hw.optimalThreadCount
        self.recommendedThreads = hw.optimalThreadCount
        self.kvQuantization = hw.defaultKVQuant
        self.recommendedKVQuant = hw.defaultKVQuant

        // Recompute recommendations on changes
        $contextWindowTokens.combineLatest($kvQuantization)
            .sink { [weak self] (ctx, kv) in
                self?.recalculateKVMemory(context: ctx, kvQuant: kv)
            }
            .store(in: &cancellables)
    }

    /// Updates dynamic recommendations based on newly inspected or loaded model
    public func updateForModel(metadata: GGUFMetadata) {
        let hw = HardwareAutoTuner.shared.detectProfile()
        let maxSafe = GGUFHeaderParser.shared.calculateMaxSafeContext(
            metadata: metadata,
            usableProcessRAMBytes: hw.maxSafeRAMLimitBytes,
            kvQuant: self.kvQuantization
        )

        DispatchQueue.main.async {
            self.maxSafeContextTokens = maxSafe
            
            // Suggest generous safe default (e.g. 50% of maximum or up to 64k/128k)
            if metadata.estimatedParamCountBillion <= 0.6 {
                self.recommendedContextTokens = min(maxSafe, 65536)
            } else if metadata.estimatedParamCountBillion <= 1.8 {
                self.recommendedContextTokens = min(maxSafe, 32768)
            } else if metadata.estimatedParamCountBillion <= 4.0 {
                self.recommendedContextTokens = min(maxSafe, 16384)
            } else {
                self.recommendedContextTokens = min(maxSafe, 8192)
            }

            self.lastKnownMetadata = metadata
            // Choose the KV quantisation for THIS model at THIS context: quality
            // where there is room, memory where there is not. Previously it stayed
            // whatever the device table suggested regardless of the model.
            let quant = GGUFHeaderParser.shared.recommendKVQuant(
                metadata: metadata,
                desiredContext: self.recommendedContextTokens,
                usableProcessRAMBytes: hw.maxSafeRAMLimitBytes
            )
            self.kvQuantization = quant
            self.recommendedKVQuant = quant
            // Do not move a context the user already set. A download completing
            // silently overwrote their choice.
            if !self.userHasChosenContext {
                self.contextWindowTokens = self.recommendedContextTokens
            }
            self.recalculateKVMemory(context: self.contextWindowTokens, kvQuant: self.kvQuantization, meta: metadata)
        }
    }

    /// Updates dynamic recommendations from a loaded llama_model (authoritative metadata)
    public func updateForLoadedModel(model: OpaquePointer, modelFileSize: UInt64, loadedContext: Int) {
        let nCtxTrain = Int(llama_model_n_ctx_train(model))
        let nLayers = Int(llama_model_n_layer(model))
        let nEmbd = Int(llama_model_n_embd(model))
        let nHeadKV = Int(llama_model_n_head_kv(model))
        let nHead = Int(llama_model_n_head(model))

        var buf = [CChar](repeating: 0, count: 256)
        llama_model_desc(model, &buf, 256)
        let desc = String(cString: buf)

        let meta = GGUFMetadata(
            architecture: Self.archFromDesc(desc),
            contextLengthTrained: nCtxTrain,
            layerCount: nLayers,
            embeddingLength: nEmbd,
            headCountKV: nHeadKV,
            headCount: nHead,
            fileSizeBytes: modelFileSize,
            estimatedParamCountBillion: 12.0 * Double(nEmbd) * Double(nEmbd) * Double(nLayers) / 1_000_000_000.0
        )

        let hw = HardwareAutoTuner.shared.detectProfile()
        let maxSafe = GGUFHeaderParser.shared.calculateMaxSafeContext(
            metadata: meta,
            usableProcessRAMBytes: hw.maxSafeRAMLimitBytes,
            kvQuant: self.kvQuantization
        )

        DispatchQueue.main.async {
            self.maxSafeContextTokens = maxSafe
            let params = meta.estimatedParamCountBillion
            if params <= 0.6 {
                self.recommendedContextTokens = min(maxSafe, 65536)
            } else if params <= 1.8 {
                self.recommendedContextTokens = min(maxSafe, 32768)
            } else if params <= 4.0 {
                self.recommendedContextTokens = min(maxSafe, 16384)
            } else {
                self.recommendedContextTokens = min(maxSafe, 8192)
            }
            // Do not clobber the live context: it was already fixed by
            // llama_init_from_model. Report what is actually loaded.
            self.lastKnownMetadata = meta
            self.contextWindowTokens = loadedContext
            self.recalculateKVMemory(context: loadedContext, kvQuant: self.kvQuantization, meta: meta)
        }
    }

    private static func archFromDesc(_ desc: String) -> String {
        let lower = desc.lowercased()
        if lower.contains("qwen") { return "qwen2" }
        if lower.contains("mistral") { return "mistral" }
        if lower.contains("gemma") { return "gemma" }
        return "llama"
    }

    public func applyPreset(_ preset: SamplingPreset) {
        selectedPreset = preset
        switch preset {
        case .reasoning:
            temperature = 0.6
            topP = 0.95
            minP = 0.05
            topK = 0
            reasoningBudgetTokens = 8192
        case .coding:
            temperature = 0.2
            topP = 0.90
            minP = 0.05
            topK = 40
            reasoningBudgetTokens = 4096
        case .creative:
            temperature = 0.8
            topP = 0.95
            minP = 0.02
            topK = 50
            reasoningBudgetTokens = 2048
        case .eval:
            temperature = 0.0
            topP = 1.0
            minP = 0.0
            topK = 1
            reasoningBudgetTokens = 0
        }
    }

    private func recalculateKVMemory(context: Int, kvQuant: String, meta: GGUFMetadata? = nil) {
        // With nothing known, keep the last figure rather than reading a phantom
        // path and publishing fallback numbers as if they were measurements.
        guard let m = meta ?? lastKnownMetadata else { return }
        let bytes = GGUFHeaderParser.shared.calculateKVCacheBytes(metadata: m, contextTokens: context, kvQuant: kvQuant)
        let mb = Double(bytes) / (1024.0 * 1024.0)
        DispatchQueue.main.async { self.estimatedKVRAMMB = mb }
    }
}
