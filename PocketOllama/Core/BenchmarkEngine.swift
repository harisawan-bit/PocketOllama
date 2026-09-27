import Foundation

public struct BenchmarkResult: Identifiable, Sendable {
    public let id = UUID()
    public let timestamp: Date
    public let socName: String
    public let modelName: String
    public let promptChars: Int
    public let ttftMs: Double
    public let tokensPerSecond: Double
    public let totalTokens: Int
    public let durationSeconds: Double
    public let isValid: Bool

    public var summary: String {
        guard isValid else { return "Benchmark failed" }
        return "\(socName) • \(String(format: "%.1f", tokensPerSecond)) tok/s • \(String(format: "%.0f", ttftMs))ms TTFT"
    }
}

public final class BenchmarkEngine: ObservableObject, @unchecked Sendable {
    public static let shared = BenchmarkEngine()

    @Published public private(set) var isRunning: Bool = false
    @Published public private(set) var lastResult: BenchmarkResult?

    private init() {}

    /// Measures the real engine. Any failure is reported as an invalid result, never faked.
    public func runBenchmark(tokenCount: Int = 128) async -> BenchmarkResult {
        await MainActor.run { self.isRunning = true }

        let prompt = "Explain quantum computing algorithms and complexity theory in concise technical bullet points."
        let hw = HardwareAutoTuner.shared.detectProfile()
        let modelName = await LlamaEngine.shared.activeModelName
        let isReady = await LlamaEngine.shared.isModelReady

        guard isReady else {
            let failed = BenchmarkResult(
                timestamp: Date(), socName: hw.socName, modelName: modelName,
                promptChars: prompt.count, ttftMs: 0, tokensPerSecond: 0,
                totalTokens: 0, durationSeconds: 0, isValid: false
            )
            await MainActor.run {
                self.lastResult = failed
                self.isRunning = false
            }
            return failed
        }

        var config = InferenceConfig(engine: ConfigEngine.shared)
        config.maxTokens = tokenCount

        let start = Date()
        var firstToken: Date?
        var produced = 0

        let stream = await LlamaEngine.shared.streamInference(prompt: "user\n\(prompt)", config: config)

        do {
            for try await delta in stream {
                if firstToken == nil, !delta.text.isEmpty || delta.reasoningText != nil {
                    firstToken = Date()
                }
                if !delta.text.isEmpty || delta.reasoningText != nil { produced += 1 }
                if delta.isFinished { break }
            }
        } catch {
            let failed = BenchmarkResult(
                timestamp: Date(), socName: hw.socName, modelName: modelName,
                promptChars: prompt.count, ttftMs: 0, tokensPerSecond: 0,
                totalTokens: 0, durationSeconds: 0, isValid: false
            )
            await MainActor.run {
                self.lastResult = failed
                self.isRunning = false
            }
            return failed
        }

        let end = Date()
        let ttftMs = firstToken.map { $0.timeIntervalSince(start) * 1000.0 } ?? 0
        let genDuration = firstToken.map { max(0.001, end.timeIntervalSince($0)) } ?? 0
        let tps = genDuration > 0 ? Double(produced) / genDuration : 0

        let result = BenchmarkResult(
            timestamp: Date(),
            socName: hw.socName,
            modelName: modelName,
            promptChars: prompt.count,
            ttftMs: ttftMs,
            tokensPerSecond: tps,
            totalTokens: produced,
            durationSeconds: end.timeIntervalSince(start),
            isValid: firstToken != nil && produced > 0
        )

        await MainActor.run {
            self.lastResult = result
            self.isRunning = false
        }

        return result
    }
}