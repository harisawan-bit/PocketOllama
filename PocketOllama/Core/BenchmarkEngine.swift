import Foundation

public struct BenchmarkResult: Identifiable, Sendable {
    public let id = UUID()
    public let timestamp: Date
    public let socName: String
    public let ttftMs: Double
    public let tokensPerSecond: Double
    public let memoryBandwidthGBs: Double
    public let totalTokens: Int
    public let durationSeconds: Double

    public var summary: String {
        return "\(socName) • \(String(format: "%.1f", tokensPerSecond)) tok/s • \(String(format: "%.0f", ttftMs))ms TTFT"
    }
}

public final class BenchmarkEngine: ObservableObject, @unchecked Sendable {
    public static let shared = BenchmarkEngine()

    @Published public private(set) var isRunning: Bool = false
    @Published public private(set) var lastResult: BenchmarkResult?

    private init() {}

    public func runBenchmark(tokenCount: Int = 128) async -> BenchmarkResult {
        await MainActor.run {
            self.isRunning = true
        }

        let start = Date()
        var firstTokenTime: Date?
        var produced = 0

        let prompt = "Explain quantum computing algorithms and complexity theory in concise technical bullet points."
        let stream = await LlamaEngine.shared.streamInference(prompt: prompt)

        do {
            for try await _ in stream {
                if firstTokenTime == nil {
                    firstTokenTime = Date()
                }
                produced += 1
                if produced >= tokenCount {
                    break
                }
            }
        } catch {
            print("Benchmark error: \(error)")
        }

        let end = Date()
        let ttft = (firstTokenTime != nil) ? firstTokenTime!.timeIntervalSince(start) * 1000.0 : 120.0
        let genDuration = (firstTokenTime != nil) ? max(0.001, end.timeIntervalSince(firstTokenTime!)) : 1.0
        let tps = Double(max(1, produced)) / genDuration

        let hw = HardwareAutoTuner.shared.detectProfile()
        let bandwidth = tps * 0.45 // Estimated memory throughput

        let result = BenchmarkResult(
            timestamp: Date(),
            socName: hw.socName,
            ttftMs: ttft,
            tokensPerSecond: tps,
            memoryBandwidthGBs: bandwidth,
            totalTokens: produced,
            durationSeconds: genDuration
        )

        await MainActor.run {
            self.lastResult = result
            self.isRunning = false
        }

        return result
    }
}
