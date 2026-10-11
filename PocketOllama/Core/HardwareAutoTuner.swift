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
    /// True when the chip was matched in the table rather than inferred from RAM.
    public let isKnownDevice: Bool
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
        //
        // These sysctls are absent on older A-series chips. Returning nil lets the
        // caller fall back to a chip-appropriate value instead of assuming the
        // total logical count, which on a 2P+4E part would run inference on
        // efficiency cores.
        let perf = sysctlInt("hw.perflevel0.logicalcpu") ?? sysctlInt("hw.perflevel0.physicalcpu")
        let eff = sysctlInt("hw.perflevel1.logicalcpu") ?? sysctlInt("hw.perflevel1.physicalcpu")
        let total = ProcessInfo.processInfo.activeProcessorCount
        guard let p = perf else {
            return CoreCounts(performance: -1, efficiency: -1, total: max(1, total))
        }
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
        // A negative sentinel means the perf-level sysctls were absent, i.e. an
        // older A-series part. Every such chip is a 2P+4E design, so 2 is both
        // correct and safe; assuming the total would push work onto the
        // efficiency cores and cut throughput roughly in half.
        let threads = cores.performance > 0 ? max(2, cores.performance) : base.fallbackThreads
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
            optimalThreadCount: threads,
            maxSafeContextTokens: base.maxSafeContextTokens,
            defaultKVQuant: base.defaultKVQuant,
            supportsSpeculative: base.supportsSpeculative,
            is8GBPlus: base.is8GBPlus,
            isKnownDevice: base.isKnownDevice
        )
    }

    // MARK: - Device table

    /// One row of the device table. Identifiers are the `hw.machine` values, taken
    /// from AppleDB and the public device-identifier list; the SoC for each entry
    /// is verified against AppleDB's per-model SoC field.
    private struct DeviceRow {
        let identifiers: Set<String>
        let soc: String
        let name: String
        let context: Int
        let kv: String
        let tier: String
        let is8GBPlus: Bool
        let speculative: Bool
        /// Threads when the perf-level sysctls are absent.
        let fallbackThreads: Int
    }

    /// Table-driven so a new device is one row, not a copy-pasted constructor.
    /// Entries are ordered newest first; the first match wins.
    private static let deviceTable: [DeviceRow] = [
        // A20 Pro - iPhone 18 Pro family. 8 GB or more.
        DeviceRow(identifiers: ["iPhone19,2", "iPhone19,3", "iPhone19,7", "iPhone19,4"],
                  soc: "A20 Pro (3nm)", name: "iPhone 18 Pro / Air (A20 Pro)",
                  context: 32768, kv: "q4_0",
                  tier: "Hermes 3 8B (Q4_K_M) / DeepSeek-R1-7B",
                  is8GBPlus: true, speculative: true, fallbackThreads: 2),

        // A19 family.
        DeviceRow(identifiers: ["iPhone18,1", "iPhone18,2"],
                  soc: "A19 Pro (3nm)", name: "iPhone 17 Pro / Pro Max",
                  context: 32768, kv: "q4_0",
                  tier: "Hermes 3 8B (Q4_K_M) / DeepSeek-R1-7B",
                  is8GBPlus: true, speculative: true, fallbackThreads: 2),
        DeviceRow(identifiers: ["iPhone18,3"],
                  soc: "A19 (3nm)", name: "iPhone 17",
                  context: 16384, kv: "q4_0",
                  tier: "Hermes 3 8B (Q4_K_M) / Llama 3.2 3B",
                  is8GBPlus: true, speculative: true, fallbackThreads: 2),
        DeviceRow(identifiers: ["iPhone18,5"],
                  soc: "A19 (3nm)", name: "iPhone 17e",
                  context: 16384, kv: "q4_0",
                  tier: "Hermes 3 3B / Llama 3.2 3B",
                  is8GBPlus: true, speculative: true, fallbackThreads: 2),
        DeviceRow(identifiers: ["iPhone18,4"],
                  soc: "A19 Pro (3nm)", name: "iPhone Air",
                  context: 16384, kv: "q4_0",
                  tier: "Hermes 3 8B (Q4_K_M) / Llama 3.2 3B",
                  is8GBPlus: true, speculative: true, fallbackThreads: 2),

        // A18 family.
        DeviceRow(identifiers: ["iPhone17,1", "iPhone17,2"],
                  soc: "A18 Pro (3nm)", name: "iPhone 16 Pro / Pro Max",
                  context: 32768, kv: "q4_0",
                  tier: "Hermes 3 8B (Q4_K_M) / DeepSeek-R1-7B",
                  is8GBPlus: true, speculative: true, fallbackThreads: 2),
        DeviceRow(identifiers: ["iPhone17,3", "iPhone17,4"],
                  soc: "A18 (3nm)", name: "iPhone 16 / 16 Plus",
                  context: 16384, kv: "q4_0",
                  tier: "Hermes 3 8B (Q4_K_M) / Llama 3.2 3B",
                  is8GBPlus: true, speculative: true, fallbackThreads: 2),
        // The 16e is an A18, not an A18 Pro. It was previously listed with the
        // 16 and 16 Plus but is a cheaper, single-camera part with 8 GB.
        DeviceRow(identifiers: ["iPhone17,5"],
                  soc: "A18 (3nm)", name: "iPhone 16e",
                  context: 16384, kv: "q4_0",
                  tier: "Hermes 3 3B / Llama 3.2 3B",
                  is8GBPlus: true, speculative: true, fallbackThreads: 2),

        // A17 Pro.
        DeviceRow(identifiers: ["iPhone16,1", "iPhone16,2"],
                  soc: "A17 Pro (3nm)", name: "iPhone 15 Pro / Pro Max",
                  context: 32768, kv: "q4_0",
                  tier: "Hermes 3 8B (Q4_K_M) / DeepSeek-R1-7B / Qwen 2.5 7B",
                  is8GBPlus: true, speculative: true, fallbackThreads: 2),

        // A16. Both the 14 Pro and the 15 carry it, with 6 GB.
        DeviceRow(identifiers: ["iPhone15,2", "iPhone15,3"],
                  soc: "A16 Bionic", name: "iPhone 14 Pro / Pro Max",
                  context: 8192, kv: "q8_0",
                  tier: "Hermes 3 3B / Qwen 2.5 3B",
                  is8GBPlus: false, speculative: false, fallbackThreads: 2),
        DeviceRow(identifiers: ["iPhone15,4", "iPhone15,5"],
                  soc: "A16 Bionic", name: "iPhone 15 / 15 Plus",
                  context: 8192, kv: "q8_0",
                  tier: "Hermes 3 3B / Llama 3.2 3B",
                  is8GBPlus: false, speculative: false, fallbackThreads: 2),

        // A15. 13 and 13 Pro are 6 GB; the 13 mini, SE 3 and 14 are 4 GB.
        DeviceRow(identifiers: ["iPhone14,2", "iPhone14,3"],
                  soc: "A15 Bionic", name: "iPhone 13 Pro / Pro Max",
                  context: 8192, kv: "q8_0",
                  tier: "Hermes 3 3B / Qwen 2.5 3B",
                  is8GBPlus: false, speculative: false, fallbackThreads: 2),
        DeviceRow(identifiers: ["iPhone14,4", "iPhone14,5"],
                  soc: "A15 Bionic", name: "iPhone 13 / 13 mini",
                  context: 8192, kv: "q8_0",
                  tier: "Llama 3.2 3B / Qwen 2.5 3B",
                  is8GBPlus: false, speculative: false, fallbackThreads: 2),
        DeviceRow(identifiers: ["iPhone14,6", "iPhone14,7", "iPhone14,8"],
                  soc: "A15 Bionic", name: "iPhone SE 3 / 14 / 14 Plus",
                  context: 8192, kv: "q8_0",
                  tier: "Llama 3.2 3B / Qwen 2.5 3B",
                  is8GBPlus: false, speculative: false, fallbackThreads: 2),

        // A14.
        DeviceRow(identifiers: ["iPhone13,1", "iPhone13,2"],
                  soc: "A14 Bionic", name: "iPhone 12 / 12 mini",
                  context: 4096, kv: "q8_0",
                  tier: "Llama 3.2 3B / Qwen 2.5 1.5B",
                  is8GBPlus: false, speculative: false, fallbackThreads: 2),
        DeviceRow(identifiers: ["iPhone13,3", "iPhone13,4"],
                  soc: "A14 Bionic", name: "iPhone 12 Pro / Pro Max",
                  context: 4096, kv: "q8_0",
                  tier: "Llama 3.2 3B / Qwen 2.5 3B",
                  is8GBPlus: false, speculative: false, fallbackThreads: 2),

        // A13. The 11 and SE 2 have 4 GB.
        DeviceRow(identifiers: ["iPhone12,1"],
                  soc: "A13 Bionic", name: "iPhone 11",
                  context: 4096, kv: "q8_0",
                  tier: "Qwen 2.5 1.5B / Llama 3.2 3B",
                  is8GBPlus: false, speculative: false, fallbackThreads: 2),
        DeviceRow(identifiers: ["iPhone12,3", "iPhone12,5"],
                  soc: "A13 Bionic", name: "iPhone 11 Pro / Pro Max",
                  context: 4096, kv: "q8_0",
                  tier: "Llama 3.2 3B / Qwen 2.5 3B",
                  is8GBPlus: false, speculative: false, fallbackThreads: 2),
        DeviceRow(identifiers: ["iPhone12,8"],
                  soc: "A13 Bionic", name: "iPhone SE 2nd Gen",
                  context: 4096, kv: "q8_0",
                  tier: "Qwen 2.5 1.5B / Llama 3.2 3B",
                  is8GBPlus: false, speculative: false, fallbackThreads: 2),

        // A12. XR is 3 GB; XS and XS Max are 4 GB.
        DeviceRow(identifiers: ["iPhone11,8"],
                  soc: "A12 Bionic", name: "iPhone XR",
                  context: 2048, kv: "q8_0",
                  tier: "Qwen 2.5 0.5B-1.5B",
                  is8GBPlus: false, speculative: false, fallbackThreads: 2),
        DeviceRow(identifiers: ["iPhone11,2", "iPhone11,4", "iPhone11,6"],
                  soc: "A12 Bionic", name: "iPhone XS / XS Max",
                  context: 2048, kv: "q8_0",
                  tier: "Qwen 2.5 0.5B-1.5B",
                  is8GBPlus: false, speculative: false, fallbackThreads: 2),

        // A11. The oldest chip that can run iOS 16.4. 2 GB on the 8, 3 GB on the X.
        DeviceRow(identifiers: ["iPhone10,1", "iPhone10,4"],
                  soc: "A11 Bionic", name: "iPhone 8",
                  context: 2048, kv: "q8_0",
                  tier: "Qwen 2.5 0.5B",
                  is8GBPlus: false, speculative: false, fallbackThreads: 2),
        DeviceRow(identifiers: ["iPhone10,2", "iPhone10,5"],
                  soc: "A11 Bionic", name: "iPhone 8 Plus",
                  context: 2048, kv: "q8_0",
                  tier: "Qwen 2.5 0.5B",
                  is8GBPlus: false, speculative: false, fallbackThreads: 2),
        DeviceRow(identifiers: ["iPhone10,3", "iPhone10,6"],
                  soc: "A11 Bionic", name: "iPhone X",
                  context: 2048, kv: "q8_0",
                  tier: "Qwen 2.5 0.5B",
                  is8GBPlus: false, speculative: false, fallbackThreads: 2),
    ]

    private func baseProfile() -> DeviceHardwareSpec {
        var size: Int = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        var machine = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.machine", &machine, &size, nil, 0)
        let identifier = String(cString: machine)

        let totalRAMBytes = ProcessInfo.processInfo.physicalMemory
        let totalRAMGB = Double(totalRAMBytes) / (1024.0 * 1024.0 * 1024.0)

        if let row = Self.deviceTable.first(where: { $0.identifiers.contains(identifier) }) {
            return DeviceHardwareSpec(
                modelIdentifier: identifier,
                marketingName: row.name,
                socName: row.soc,
                gpuName: Self.metalGPUName(),
                totalRAMGB: totalRAMGB,
                maxSafeRAMLimitBytes: Self.safeRAMLimit(totalRAMGB: totalRAMGB),
                recommendedModelTier: row.tier,
                optimalThreadCount: row.fallbackThreads,
                maxSafeContextTokens: row.context,
                defaultKVQuant: row.kv,
                supportsSpeculative: row.speculative,
                is8GBPlus: row.is8GBPlus,
                isKnownDevice: true
            )
        }

        // Unknown device: an iPad, a device released after this table, or a
        // simulator. Do not name a chip. Band by measured RAM, which is what
        // actually governs how large a model fits.
        //
        // The previous fallback had a single 7.2 GB cut-off, so a 2 GB phone and
        // a 6 GB phone got the same 3B recommendation and the same 8192 context.
        let band = Self.ramBand(totalRAMGB: totalRAMGB)
        return DeviceHardwareSpec(
            modelIdentifier: identifier,
            marketingName: "Apple Silicon (\(String(format: "%.1f", totalRAMGB)) GB)",
            socName: "Apple Silicon",
            gpuName: Self.metalGPUName(),
            totalRAMGB: totalRAMGB,
            maxSafeRAMLimitBytes: Self.safeRAMLimit(totalRAMGB: totalRAMGB),
            recommendedModelTier: band.tier,
            optimalThreadCount: 2,
            maxSafeContextTokens: band.context,
            defaultKVQuant: band.kv,
            supportsSpeculative: band.context >= 16384,
            is8GBPlus: totalRAMGB >= 7.2,
            isKnownDevice: false
        )
    }

    /// Delegates to the shared, CI-tested band table.
    private static func ramBand(totalRAMGB: Double) -> (context: Int, kv: String, tier: String) {
        let b = RAMBands.band(totalRAMGB: totalRAMGB)
        return (b.context, b.kv, b.tier)
    }

    /// The lowest iOS version this app can run on, and why.
    ///
    /// The bundled llama.cpp XCFramework declares MinimumOSVersion 16.4 in its own
    /// Info.plist, which its build script sets from IOS_MIN_OS_VERSION. A lower
    /// deployment target cannot link or run it, so 16.4 is a hard floor set by the
    /// dependency, not a product decision.
    public static let minimumSupportedOS = "16.4"
}
