import UIKit

public final class AppDelegate: NSObject, UIApplicationDelegate {
    public func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // 1. Bulletproof SIGPIPE immunity (survives sudden laptop disconnects)
        signal(SIGPIPE, SIG_IGN)
        
        // 2. Initialize Hardware & Thermal Governors
        _ = HardwareAutoTuner.shared.detectProfile()
        _ = ThermalGovernor.shared
        _ = MemoryScavenger.shared.purgeAndScavengeRAM()

        print("[PocketOllama] Initialized with Apple Silicon Metal acceleration and Darwin VM memory lock.")
        return true
    }

    public func applicationDidReceiveMemoryWarning(_ application: UIApplication) {
        print("[PocketOllama] Kernel memory pressure alert. Triggering RAM scavenger...")
        MemoryScavenger.shared.purgeAndScavengeRAM()
    }
}
