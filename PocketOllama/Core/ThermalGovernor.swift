import Foundation
import Combine

public enum ThermalSafetyTier: String, Sendable {
    case nominal = "Nominal • Peak Speed"
    case fair = "Fair • Optimal"
    case serious = "Serious • Throttled"
    case critical = "Critical • Cooldown"
}

public final class ThermalGovernor: ObservableObject, @unchecked Sendable {
    public static let shared = ThermalGovernor()

    @Published public private(set) var currentThermalTier: ThermalSafetyTier = .nominal
    @Published public private(set) var activeThreadCount: Int = 4
    @Published public private(set) var interTokenCooldownMs: UInt32 = 0
    @Published public private(set) var isThrottled: Bool = false

    private var baseThreadCount: Int = 4
    private var cancellables = Set<AnyCancellable>()

    private init() {
        let profile = HardwareAutoTuner.shared.detectProfile()
        self.baseThreadCount = profile.optimalThreadCount
        self.activeThreadCount = profile.optimalThreadCount

        NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification)
            .sink { [weak self] _ in
                self?.evaluateThermalState()
            }
            .store(in: &cancellables)

        evaluateThermalState()
    }

    public func setBaseThreads(_ count: Int) {
        self.baseThreadCount = max(1, count)
        evaluateThermalState()
    }

    public func evaluateThermalState() {
        let state = ProcessInfo.processInfo.thermalState

        switch state {
        case .nominal:
            currentThermalTier = .nominal
            activeThreadCount = baseThreadCount
            interTokenCooldownMs = 0
            isThrottled = false
            
        case .fair:
            currentThermalTier = .fair
            activeThreadCount = baseThreadCount
            interTokenCooldownMs = 0
            isThrottled = false
            
        case .serious:
            currentThermalTier = .serious
            activeThreadCount = max(2, baseThreadCount - 1)
            interTokenCooldownMs = 4
            isThrottled = true

        case .critical:
            currentThermalTier = .critical
            activeThreadCount = 2
            interTokenCooldownMs = 12
            isThrottled = true

        @unknown default:
            break
        }
    }

    public func yieldIfThrottled() async {
        if interTokenCooldownMs > 0 {
            try? await Task.sleep(nanoseconds: UInt64(interTokenCooldownMs) * 1_000_000)
        }
    }
}
