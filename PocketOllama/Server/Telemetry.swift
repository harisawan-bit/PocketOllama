import Foundation
import Combine
import MachO

public final class TelemetryManager: ObservableObject, @unchecked Sendable {
    public static let shared = TelemetryManager()

    @Published public private(set) var tokensPerSecond: Double = 0.0
    @Published public private(set) var ramUsedMB: Double = 0.0
    @Published public private(set) var ramAvailableMB: Double = 0.0
    @Published public private(set) var totalTokensServed: UInt64 = 0
    @Published public private(set) var sparklineHistory: [Double] = Array(repeating: 0.0, count: 20)

    private var timer: AnyCancellable?

    private init() {
        startPolling()
    }

    private var windowStart = Date()
    private var windowTokens = 0

    /// Begins a decode window. Throughput is measured from here so prefill time is
    /// excluded, matching how the benchmark computes tokens per second.
    public func beginMeasurement() {
        windowStart = Date()
        windowTokens = 0
    }

    /// Records one decoded token and publishes a live rolling rate.
    public func recordTokenTick() {
        windowTokens += 1
        let elapsed = Date().timeIntervalSince(windowStart)
        guard elapsed > 0 else { return }
        let tps = Double(windowTokens) / elapsed
        DispatchQueue.main.async {
            self.tokensPerSecond = tps
            self.totalTokensServed += 1
            if self.sparklineHistory.count >= 20 {
                self.sparklineHistory.removeFirst()
            }
            self.sparklineHistory.append(tps)
        }
    }

    public func recordTokensGenerated(count: Int, durationSeconds: Double) {
        DispatchQueue.main.async {
            self.totalTokensServed += UInt64(max(0, count - self.windowTokens))
        }
    }

    private func startPolling() {
        timer = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.pollSystemRAM()
            }
    }

    private func pollSystemRAM() {
        let availBytes = MemoryScavenger.shared.getAvailableMemoryBytes()
        self.ramAvailableMB = Double(availBytes) / (1024 * 1024)

        // Read physical process footprint
        var taskInfo = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &taskInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        if result == KERN_SUCCESS {
            self.ramUsedMB = Double(taskInfo.phys_footprint) / (1024 * 1024)
        }
    }
}
