import Foundation
import UIKit
import Metal

public struct DeviceHardwareSpec: Sendable, Codable {
    public let modelIdentifier: String
    public let marketingName: String
    public let socName: String
    /// Real GPU name from Metal. There is no API for a core count on iOS,
    /// so this is a name, not an invented number.
    public let gpuName: String
    public let totalRAMGB: Double
    public let maxSafeRAMLimitBytes: UInt64
    public let recommendedModelTier: String
    /// Always derived from the real performance cores by detectProfile. The
    /// lookup table omits it; the default only keeps the memberwise init valid
    /// for those call sites and is never the value that ships.
    public var optimalThreadCount: Int = 2
    public let maxSafeContextTokens: Int
    public let defaultKVQuant: String
    public let supportsSpeculative: Bool
    public let is8GBPlus: Bool
}

public final class HardwareAutoTuner: @unchecked Sendable {
    public static let shared = HardwareAutoTuner()
    
    private init() {}

    /// Real core counts, read from the OS rather than assumed.
    public struct CoreCounts: Sendable {
        public let performance: Int
        public let efficiency: Int
        public let total: Int
    }

    public static func detectCoreCounts() -> CoreCounts {
        // ProcessInfo.performanceCoreCount is not exposed on iOS, so read the
        // Darwin perf levels directly: hw.perflevel0 is the performance cluster
        // and hw.perflevel1 the efficiency cluster on every Apple Silicon phone.
        let perf = sysctlInt("hw.perflevel0.logicalcpu") ?? sysctlInt("hw.perflevel0.physicalcpu")
        let eff = sysctlInt("hw.perflevel1.logicalcpu") ?? sysctlInt("hw.perflevel1.physicalcpu")
        let total = ProcessInfo.processInfo.activeProcessorCount
        let p = perf ?? total
        return CoreCounts(performance: max(1, p),
                          efficiency: max(0, eff ?? max(0, total - p)),
                          total: max(1, total))
    }

    /// The real GPU, straight from Metal. There is no iOS API for a GPU core
    /// count, so the app reports the device name rather than inventing a number.
    public static func metalGPUName() -> String {
        metalDeviceName ?? "Apple GPU"
    }

    private static let metalDeviceName: String? = {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        return device.name
    }()

    /// Safe process budget derived from measured RAM.
    ///
    /// iOS jetsams a process well before physical RAM runs out, and the ceiling
    /// moves with both device RAM and what else is resident. 45% of physical is a
    /// conservative planning figure; the authoritative check is the post-load
    /// measurement against os_proc_available_memory, not this number.
    public static func safeRAMLimit(totalRAMGB: Double) -> UInt64 {
        UInt64(max(1.5, min(totalRAMGB * 0.45, 12.0)) * 1024 * 1024 * 1024)
    }

    private static func sysctlInt(_ name: String) -> Int? {
        var value: Int = 0
        var size = MemoryLayout<Int>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0, value > 0 else { return nil }
        return value
    }

    /// Wraps the lookup table so the thread count reflects the real performance
    /// cores instead of a hardcoded 2, and reports the OS core counts truthfully.
    public func detectProfile() -> DeviceHardwareSpec {
        let base = baseProfile()
        let cores = Self.detectCoreCounts()
        return DeviceHardwareSpec(
            modelIdentifier: base.modelIdentifier,
            marketingName: base.marketingName,
            socName: base.socName,
            gpuName: base.gpuName,
            totalRAMGB: base.totalRAMGB,
            maxSafeRAMLimitBytes: base.maxSafeRAMLimitBytes,
            recommendedModelTier: base.recommendedModelTier,
            // Max juice when cool; the thermal governor scales this back as the
            // phone heats up. Every device previously got 2 regardless of silicon.
            optimalThreadCount: max(2, cores.performance),
            maxSafeContextTokens: base.maxSafeContextTokens,
            defaultKVQuant: base.defaultKVQuant,
            supportsSpeculative: base.supportsSpeculative,
            is8GBPlus: base.is8GBPlus
        )
    }

    private func baseProfile() -> DeviceHardwareSpec {
        var size: Int = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        var machine = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.machine", &machine, &size, nil, 0)
        let identifier = String(cString: machine)
        
        let totalRAMBytes = ProcessInfo.processInfo.physicalMemory
        let totalRAMGB = Double(totalRAMBytes) / (1024.0 * 1024.0 * 1024.0)
        
        switch identifier {
        case "iPhone16,1", "iPhone16,2": // iPhone 15 Pro, iPhone 15 Pro Max (A17 Pro)
            return DeviceHardwareSpec(
                modelIdentifier: identifier,
                marketingName: "iPhone 15 Pro / Pro Max",
                socName: "A17 Pro (3nm)",
                gpuName: Self.metalGPUName(),
                totalRAMGB: totalRAMGB,
                maxSafeRAMLimitBytes: Self.safeRAMLimit(totalRAMGB: totalRAMGB),
                recommendedModelTier: "Hermes 3 8B (Q4_K_M) / DeepSeek-R1-7B / Qwen 2.5 7B",
                maxSafeContextTokens: 32768,
                defaultKVQuant: "q4_0",
                supportsSpeculative: true,
                is8GBPlus: true
            )

        case "iPhone17,1", "iPhone17,2": // iPhone 16 Pro, 16 Pro Max (A18 Pro)
            return DeviceHardwareSpec(
                modelIdentifier: identifier,
                marketingName: "iPhone 16 Pro / Pro Max",
                socName: "A18 Pro (3nm)",
                gpuName: Self.metalGPUName(),
                totalRAMGB: totalRAMGB,
                maxSafeRAMLimitBytes: Self.safeRAMLimit(totalRAMGB: totalRAMGB),
                recommendedModelTier: "Hermes 3 8B (Q4_K_M) / DeepSeek-R1-7B",
                maxSafeContextTokens: 32768,
                defaultKVQuant: "q4_0",
                supportsSpeculative: true,
                is8GBPlus: true
            )
            
        case "iPhone17,3", "iPhone17,4", "iPhone17,5": // iPhone 16, 16 Plus (A18)
            return DeviceHardwareSpec(
                modelIdentifier: identifier,
                marketingName: "iPhone 16 / 16 Plus",
                socName: "A18",
                gpuName: Self.metalGPUName(),
                totalRAMGB: totalRAMGB,
                maxSafeRAMLimitBytes: Self.safeRAMLimit(totalRAMGB: totalRAMGB),
                recommendedModelTier: "Hermes 3 8B (Q4_K_M) / Llama 3.2 3B",
                maxSafeContextTokens: 16384,
                defaultKVQuant: "q4_0",
                supportsSpeculative: true,
                is8GBPlus: true
            )
            
        case "iPhone15,4", "iPhone15,5": // iPhone 15, 15 Plus (A16 Bionic - 6GB)
            return DeviceHardwareSpec(
                modelIdentifier: identifier,
                marketingName: "iPhone 15 / 15 Plus",
                socName: "A16 Bionic",
                gpuName: Self.metalGPUName(),
                totalRAMGB: totalRAMGB,
                maxSafeRAMLimitBytes: Self.safeRAMLimit(totalRAMGB: totalRAMGB),
                recommendedModelTier: "Hermes 3 3B / Llama 3.2 3B",
                maxSafeContextTokens: 8192,
                defaultKVQuant: "q8_0",
                supportsSpeculative: false,
                is8GBPlus: false
            )
            
        case "iPhone15,2", "iPhone15,3": // iPhone 14 Pro, 14 Pro Max (A16 Bionic - 6GB)
            return DeviceHardwareSpec(
                modelIdentifier: identifier,
                marketingName: "iPhone 14 Pro / Pro Max",
                socName: "A16 Bionic",
                gpuName: Self.metalGPUName(),
                totalRAMGB: totalRAMGB,
                maxSafeRAMLimitBytes: Self.safeRAMLimit(totalRAMGB: totalRAMGB),
                recommendedModelTier: "Hermes 3 3B / Qwen 2.5 3B",
                maxSafeContextTokens: 8192,
                defaultKVQuant: "q8_0",
                supportsSpeculative: false,
                is8GBPlus: false
            )
            
        default:
            // Unknown device. Do not name a chip: an iPad Pro M4 or an iPhone 17
            // used to land here and be reported as "A17 Pro" with a guessed core
            // count. Derive the limits from measured RAM and leave the SoC unnamed.
            let big = totalRAMGB >= 7.2
            return DeviceHardwareSpec(
                modelIdentifier: identifier,
                marketingName: "Apple Silicon (\(String(format: "%.1f", totalRAMGB)) GB)",
                socName: "Apple Silicon",
                    gpuName: Self.metalGPUName(),
                totalRAMGB: totalRAMGB,
                maxSafeRAMLimitBytes: Self.safeRAMLimit(totalRAMGB: totalRAMGB),
                recommendedModelTier: big ? "Hermes 3 8B / DeepSeek-R1" : "Llama 3.2 3B / Qwen 2.5 3B",
                maxSafeContextTokens: big ? 32768 : 8192,
                defaultKVQuant: big ? "q4_0" : "q8_0",
                supportsSpeculative: false,
                is8GBPlus: big
            )
        }
    }
}
