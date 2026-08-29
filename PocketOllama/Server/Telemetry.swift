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

    public func recordTokensGenerated(count: Int, durationSeconds: Double) {
        let tps = (durationSeconds > 0) ? Double(count) / durationSeconds : 0
        DispatchQueue.main.async {
            self.tokensPerSecond = tps
            self.totalTokensServed += UInt64(count)
            self.sparklineHistory.removeFirst()
            self.sparklineHistory.append(tps)
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
