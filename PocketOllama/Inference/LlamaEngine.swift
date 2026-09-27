import Foundation
import llama

public struct InferenceConfig: Sendable {
    public var temperature: Float = 0.6
    public var topP: Float = 0.95
    public var minP: Float = 0.05
    public var topK: Int32 = 40
    public var maxTokens: Int = 2048
    public var returnLogprobs: Bool = false
    public var stopTokens: [String] = []

    public init() {}

    public init(engine: ConfigEngine) {
        temperature = engine.temperature
        topP = engine.topP
        minP = engine.minP
        topK = engine.topK
        maxTokens = engine.reasoningBudgetTokens > 0 ? min(engine.reasoningBudgetTokens, 4096) : 2048
    }
}

public struct TokenDelta: Sendable {
    public let text: String
    public let reasoningText: String?
    public let isThinking: Bool
    public let isFinished: Bool
}

public enum LlamaEngineError: LocalizedError {
    case fileNotFound(String)
    case loadFailed(String)
    case contextInitFailed
    case notLoaded
    case busy
    case tokenizeFailed
    case decodeFailed

    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let p): return "GGUF file not found: \(p)"
        case .loadFailed(let p): return "Could not load model: \(p)"
        case .contextInitFailed: return "Could not create inference context. Not enough available memory for the requested context size."
        case .notLoaded: return "No model loaded"
        case .busy: return "Model is already generating"
        case .tokenizeFailed: return "Tokenization failed"
        case .decodeFailed: return "Inference decode failed"
        }
    }
}

public actor LlamaEngine {
    public static let shared = LlamaEngine()

    private var model: OpaquePointer?
    private var ctx: OpaquePointer?
    private var vocab: OpaquePointer?
    private var loadedModelPath = ""
    private var activeContextSize = 4096
    private var isGenerating = false
    private var lastPromptTokens = 0

    private init() {
        llama_backend_init()
    }

    deinit {
        if let c = ctx { llama_free(c) }
        if let m = model { llama_model_free(m) }
    }

    public var isModelReady: Bool { ctx != nil }

    /// Prompt and completion token counts from the most recent generation.
    public var lastUsage: (prompt: Int, completion: Int) { (lastPromptTokens, lastCompletionTokens) }
    private var lastCompletionTokens = 0
    private var cancelRequested = false
    public var isBusy: Bool { isGenerating }

    /// Stops the current generation at the next token boundary.
    public func cancelGeneration() {
        cancelRequested = true
    }
    public var contextSize: Int { activeContextSize }

    public var activeModelName: String {
        loadedModelPath.isEmpty ? "No model loaded" : (loadedModelPath as NSString).lastPathComponent
    }

    public func loadModel(path: String, targetContext: Int? = nil) async throws {
        guard FileManager.default.fileExists(atPath: path) else {
            throw LlamaEngineError.fileNotFound(path)
        }
        guard !isGenerating else { throw LlamaEngineError.busy }

        await unloadModel()

        let fileSize = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? UInt64) ?? 0
        let ctxTokens = targetContext ?? ConfigEngine.shared.contextWindowTokens

        // Advisory only. The model shape is unknown here, so this is sized from the
        // device tier and was rejecting small models at large contexts that fit
        // fine. The authoritative check runs after the model is loaded, using the
        // real dimensions, before any context memory is committed.
        let budget = JetsamShield.shared.validateMemoryBudget(
            modelFileSizeBytes: fileSize,
            requestedContextTokens: ctxTokens,
            kvQuant: ConfigEngine.shared.kvQuantization
        )
        if !budget.isSafe {
            print("[PocketOllama] Pre-load memory estimate is pessimistic: \(budget.errorMessage ?? "")")
        }

        var mparams = llama_model_default_params()
        mparams.n_gpu_layers = 999

        // Honour the mlock setting. llama.cpp gates this on device support, so a
        // device that cannot lock pages silently falls back to plain mmap.
        if ConfigEngine.shared.enableMemoryLock, llama_supports_mlock() {
            mparams.load_mode = LLAMA_LOAD_MODE_MMAP_MLOCK
        } else {
            mparams.load_mode = LLAMA_LOAD_MODE_MMAP
        }

        guard let m = llama_model_load_from_file(path, mparams) else {
            throw LlamaEngineError.loadFailed((path as NSString).lastPathComponent)
        }

        // Exact memory check now that the real dimensions are known. The pre-load
        // check has to guess the model shape, which rejected small models at large
        // contexts that actually fitted comfortably.
        let exactKV = GGUFHeaderParser.shared.calculateKVCacheBytes(
            metadata: GGUFMetadata(
                architecture: "", contextLengthTrained: 0,
                layerCount: Int(llama_model_n_layer(m)),
                embeddingLength: Int(llama_model_n_embd(m)),
                headCountKV: Int(llama_model_n_head_kv(m)),
                headCount: Int(llama_model_n_head(m)),
                fileSizeBytes: fileSize, estimatedParamCountBillion: 0
            ),
            contextTokens: ctxTokens,
            kvQuant: ConfigEngine.shared.kvQuantization
        )
        let availableNow = MemoryScavenger.shared.getAvailableMemoryBytes()
        if availableNow < exactKV + JetsamShield.shared.safetyMarginBytes {
            llama_model_free(m)
            throw NSError(domain: "PocketOllama", code: 413, userInfo: [NSLocalizedDescriptionKey:
                "Not enough free memory for a \(ctxTokens)-token context at this KV quantisation: "
                + "needs \(exactKV / (1024 * 1024)) MB for the cache plus "
                + "\(JetsamShield.shared.safetyMarginBytes / (1024 * 1024)) MB headroom, "
                + "but only \(availableNow / (1024 * 1024)) MB is free. Reduce the context or use a smaller model."])
        }

        var cparams = llama_context_default_params()
        cparams.n_ctx = UInt32(ctxTokens)
        // Prefill batch was displayed in Engine Configuration but never applied.
        let batch = max(32, ConfigEngine.shared.prefillBatchSize)
        cparams.n_batch = UInt32(batch)
        cparams.n_ubatch = UInt32(min(batch, 512))
        // The thermal governor's cap now actually applies, so the thread count the
        // dashboard reports is the one the context runs with.
        let threads = max(1, min(ConfigEngine.shared.threadCount,
                                 ThermalGovernor.shared.activeThreadCount))
        cparams.n_threads = Int32(threads)
        cparams.n_threads_batch = Int32(threads)

        // Apply the chosen KV cache quantisation. Leaving this at the f16 default
        // is what the "q4_0" recommendation was meant to avoid, but it was never
        // passed through, so the setting did nothing.
        cparams.type_k = Self.ggmlType(forKVQuant: ConfigEngine.shared.kvQuantization)
        cparams.type_v = cparams.type_k

        guard let c = llama_init_from_model(m, cparams) else {
            llama_model_free(m)
            throw LlamaEngineError.contextInitFailed
        }

        model = m
        ctx = c
        vocab = llama_model_get_vocab(m)
        loadedModelPath = path
        activeContextSize = ctxTokens

        ConfigEngine.shared.updateForLoadedModel(model: m, modelFileSize: fileSize, loadedContext: ctxTokens)

        // Remember this choice so the next launch restores the model the user
        // actually had loaded rather than an arbitrary one from the folder.
        UserDefaults.standard.set((path as NSString).lastPathComponent, forKey: "poLastLoadedModel")
    }

    public func unloadModel() async {
        if let c = ctx { llama_free(c); ctx = nil }
        if let m = model { llama_model_free(m); model = nil }
        vocab = nil
        loadedModelPath = ""
        MemoryScavenger.shared.purgeAndScavengeRAM(aggressive: ConfigEngine.shared.enableDarwinBalloonPurge)
    }

    public func loadedModelInfo() -> (desc: String, nCtxTrain: Int, nLayers: Int, nEmbd: Int, nHeadKV: Int, nVocab: Int)? {
        guard let m = model, let v = vocab else { return nil }
        var buf = [CChar](repeating: 0, count: 256)
        llama_model_desc(m, &buf, 256)
        return (
            String(cString: buf),
            Int(llama_model_n_ctx_train(m)),
            Int(llama_model_n_layer(m)),
            Int(llama_model_n_embd(m)),
            Int(llama_model_n_head_kv(m)),
            Int(llama_vocab_n_tokens(v))
        )
    }

    public func streamInference(prompt: String, config: InferenceConfig = InferenceConfig()) -> AsyncThrowingStream<TokenDelta, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                guard let ctx, let model, let vocab else {
                    continuation.finish(throwing: LlamaEngineError.notLoaded)
                    return
                }
                guard !isGenerating else {
                    continuation.finish(throwing: LlamaEngineError.busy)
                    return
                }
                isGenerating = true
                cancelRequested = false
                lastPromptTokens = 0
                lastCompletionTokens = 0
                defer { isGenerating = false }

                do {
                    try await generate(
                        prompt: prompt,
                        config: config,
                        ctx: ctx,
                        model: model,
                        vocab: vocab,
                        contextWindow: activeContextSize,
                        into: continuation
                    )
                } catch {
                    continuation.finish(throwing: error)
                    return
                }
                continuation.finish()
            }
            // A dropped client cancels the decode loop deterministically now,
            // rather than relying on the producer task noticing the consumer is gone.
            // onTermination is a non-isolated @Sendable closure, so the actor state
            // has to be hopped onto.
            continuation.onTermination = { _ in
                task.cancel()
                Task { [weak self] in self?.cancelRequested = true }
            }
        }
    }

    /// Maps a KV quantisation name onto a ggml type, falling back to f16.
    private static func ggmlType(forKVQuant name: String) -> ggml_type {
        switch name.lowercased() {
        case "q4_0": return GGML_TYPE_Q4_0
        case "q8_0": return GGML_TYPE_Q8_0
        default: return GGML_TYPE_F16
        }
    }

    private func generate(
        prompt: String,
        config: InferenceConfig,
        ctx: OpaquePointer,
        model: OpaquePointer,
        vocab: OpaquePointer,
        contextWindow: Int,
        into continuation: AsyncThrowingStream<TokenDelta, Error>.Continuation
    ) async throws {
        let formatted = Self.formatPrompt(prompt, model: model)
        let byteCount = formatted.utf8.count
        guard byteCount > 0 else { throw LlamaEngineError.tokenizeFailed }

        var tokens = [llama_token](repeating: 0, count: max(64, byteCount + 32))
        var n = llama_tokenize(vocab, formatted, Int32(byteCount), &tokens, Int32(tokens.count), true, true)
        if n < 0 {
            tokens = [llama_token](repeating: 0, count: Int(-n) + 32)
            n = llama_tokenize(vocab, formatted, Int32(byteCount), &tokens, Int32(tokens.count), true, true)
        }
        guard n > 0 else { throw LlamaEngineError.tokenizeFailed }

        // Leave headroom in the KV cache so generation cannot overflow it.
        let reserve = min(config.maxTokens, 1024)
        let promptBudget = max(1, contextWindow - reserve)
        if Int(n) > promptBudget {
            // Dropping the leading tokens would delete the system prompt and the
            // start of the conversation, so drop from the middle instead and keep
            // the instructions at the head and the question at the tail.
            let trimmed = PromptCompaction.compactTokenWindow(tokens, limit: promptBudget)
            tokens = trimmed
            n = Int32(trimmed.count)
        }

        llama_memory_clear(llama_get_memory(ctx), true)
        lastPromptTokens = Int(n)

        var i = 0
        while i < Int(n) {
            if Task.isCancelled || cancelRequested { return }
            let chunk = min(256, Int(n) - i)
            let batch = llama_batch_get_one(&tokens[i], Int32(chunk))
            if llama_decode(ctx, batch) != 0 { throw LlamaEngineError.decodeFailed }
            i += chunk
        }

        let chain = llama_sampler_chain_init(llama_sampler_chain_default_params())
        defer { llama_sampler_free(chain) }
        if config.topK > 0 {
            llama_sampler_chain_add(chain, llama_sampler_init_top_k(config.topK))
        }
        llama_sampler_chain_add(chain, llama_sampler_init_top_p(config.topP, 1))
        llama_sampler_chain_add(chain, llama_sampler_init_min_p(config.minP, 1))
        llama_sampler_chain_add(chain, llama_sampler_init_temp(config.temperature))
        llama_sampler_chain_add(chain, llama_sampler_init_dist(UInt32.random(in: 1...UInt32.max)))

        var produced = 0
        var full = ""
        var splitter = ReasoningSplitter()
        var utf8Buffer = PartialUTF8Decoder()

        while produced < config.maxTokens {
            if Task.isCancelled || cancelRequested {
                lastCompletionTokens = produced
                return
            }

            await ThermalGovernor.shared.yieldIfThrottled()

            let id = llama_sampler_sample(chain, ctx, -1)
            if llama_vocab_is_eog(vocab, id) { break }
            llama_sampler_accept(chain, id)

            var pieceBuf = [CChar](repeating: 0, count: 64)
            let pieceLen = llama_token_to_piece(vocab, id, &pieceBuf, Int32(pieceBuf.count), 0, false)
            let pieceBytes = pieceLen > 0
                ? pieceBuf.prefix(Int(pieceLen)).map { UInt8(bitPattern: $0) }
                : []
            // Byte-fallback BPE splits multi-byte characters across tokens, so the
            // tail of a piece may be an incomplete sequence. Hold it back until
            // the continuation token completes it.
            utf8Buffer.append(contentsOf: pieceBytes)
            let piece = utf8Buffer.drainDecodable()

            var next = id
            let batch = llama_batch_get_one(&next, 1)
            if llama_decode(ctx, batch) != 0 { throw LlamaEngineError.decodeFailed }
            produced += 1

            guard !piece.isEmpty else { continue }

            let combined = full + piece
            if let stop = Self.matchStop(combined, stopTokens: config.stopTokens) {
                let trimmed = String(combined.dropLast(stop.count))
                let finalSplit = ReasoningSplitter().replay(trimmed)
                lastCompletionTokens = produced
                continuation.yield(TokenDelta(
                    text: finalSplit.text,
                    reasoningText: finalSplit.reasoning,
                    isThinking: finalSplit.isThinking,
                    isFinished: true
                ))
                return
            }
            full = combined

            let parts = splitter.push(piece)
            if !parts.text.isEmpty || parts.reasoning != nil {
                continuation.yield(TokenDelta(
                    text: parts.text,
                    reasoningText: parts.reasoning,
                    isThinking: parts.isThinking,
                    isFinished: false
                ))
            }
        }

        lastCompletionTokens = produced

        let tail = splitter.flush()
        continuation.yield(TokenDelta(
            text: tail.text,
            reasoningText: tail.reasoning,
            isThinking: tail.isThinking,
            isFinished: true
        ))
    }

    private static func matchStop(_ text: String, stopTokens: [String]) -> String? {
        for token in stopTokens where !token.isEmpty && text.hasSuffix(token) {
            return token
        }
        return nil
    }

    private static func formatPrompt(_ prompt: String, model: OpaquePointer) -> String {
        let template = llama_model_chat_template(model, nil).map { String(cString: $0) } ?? "chatml"

        var messages: [llama_chat_message] = []
        var owned: [UnsafeMutablePointer<CChar>] = []

        func append(role: String, content: String) {
            let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            guard let r = strdup(role), let c = strdup(trimmed) else { return }
            owned.append(r)
            owned.append(c)
            messages.append(llama_chat_message(role: UnsafePointer(r), content: UnsafePointer(c)))
        }

        // The server hands us role-prefixed blocks. Unlabelled blocks stay with the current role.
        let knownRoles = ["system", "user", "assistant", "tool"]
        var currentRole = "user"
        var buffer = ""

        func flush() {
            if !buffer.isEmpty {
                append(role: currentRole, content: buffer)
                buffer = ""
            }
        }

        for block in prompt.components(separatedBy: "\n\n") {
            let trimmed = block.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let head = trimmed.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
            if head.count == 2 {
                let label = head[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let body = String(head[1]).trimmingCharacters(in: .whitespacesAndNewlines)
                if knownRoles.contains(label) {
                    flush()
                    currentRole = label
                    append(role: label, content: body)
                    continue
                }
            }
            buffer += (buffer.isEmpty ? "" : "\n\n") + trimmed
        }
        flush()

        if messages.isEmpty {
            append(role: "user", content: prompt)
        }

        defer { owned.forEach { free($0) } }

        var bufSize = max(4096, prompt.utf8.count * 2 + 1024)
        var buf = [CChar](repeating: 0, count: bufSize)
        var needed = llama_chat_apply_template(template, messages, messages.count, true, &buf, Int32(bufSize))
        if needed >= bufSize {
            bufSize = Int(needed) + 1
            buf = [CChar](repeating: 0, count: bufSize)
            needed = llama_chat_apply_template(template, messages, messages.count, true, &buf, Int32(bufSize))
        }
        return needed > 0 ? String(cString: buf) : prompt
    }
}

/// Splits a token stream into visible content and reasoning traces, holding back partial tags.
struct ReasoningSplitter {
    private static let openTags = ["<thinking>", "<think>", "<scratchpad>", "<plan>"]
    private static let closeTags = ["</thinking>", "</think>", "</scratchpad>", "</plan>"]

    private var inside = false
    private var pending = ""

    mutating func push(_ piece: String) -> (text: String, reasoning: String?, isThinking: Bool) {
        pending += piece
        let emit = drain()
        if inside {
            return ("", emit.isEmpty ? nil : emit, true)
        }
        return (emit, nil, false)
    }

    /// Re-derive the split for a corrected (stop-trimmed) text. Used once, at the end.
    func replay(_ fullText: String) -> (text: String, reasoning: String?, isThinking: Bool) {
        var outText = ""
        var outReasoning = ""
        var scan = Substring(fullText)
        var isIn = false

        while let found = nextTag(in: String(scan)) {
            let before = String(scan[..<found.range.lowerBound])
            if isIn { outReasoning += before } else { outText += before }
            isIn = found.isOpen
            scan = scan[found.range.upperBound...]
        }
        let rest = String(scan)
        if isIn { outReasoning += rest } else { outText += rest }

        return (outText, outReasoning.isEmpty ? nil : outReasoning, isIn)
    }

    mutating func flush() -> (text: String, reasoning: String?, isThinking: Bool) {
        let emit = pending
        pending = ""
        if inside {
            return ("", emit.isEmpty ? nil : emit, true)
        }
        return (emit, nil, false)
    }

    private mutating func drain() -> String {
        var out = ""
        while let found = nextTag(in: pending) {
            out += String(pending[..<found.range.lowerBound])
            inside = found.isOpen
            pending = String(pending[found.range.upperBound...])
        }

        // Hold back a tail that could begin a tag so it is never split across tokens.
        let candidates = inside ? (Self.closeTags + Self.openTags) : (Self.openTags + Self.closeTags)
        for tag in candidates {
            let maxKeep = min(tag.count - 1, pending.count)
            guard maxKeep > 0 else { continue }
            for keep in stride(from: maxKeep, through: 1, by: -1) {
                if pending.hasSuffix(String(tag.prefix(keep))) {
                    out += String(pending.dropLast(keep))
                    pending = String(pending.suffix(keep))
                    return out
                }
            }
        }
        out += pending
        pending = ""
        return out
    }

    private func nextTag(in s: String) -> (range: Range<String.Index>, isOpen: Bool)? {
        var best: (Range<String.Index>, Bool)?
        for tag in Self.openTags {
            if let r = s.range(of: tag), best == nil || r.lowerBound < best!.0.lowerBound {
                best = (r, true)
            }
        }
        for tag in Self.closeTags {
            if let r = s.range(of: tag), best == nil || r.lowerBound < best!.0.lowerBound {
                best = (r, false)
            }
        }
        return best
    }
}
