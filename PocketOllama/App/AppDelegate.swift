import UIKit
import AVFoundation

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

        // 3. Configure Audio Session for Uninterruptible Overnight Runs
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playback,
                mode: .default,
                options: [.mixWithOthers, .duckOthers]
            )
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("[PocketOllama] Audio session note: \(error)")
        }

        print("[PocketOllama] Initialized with Apple Silicon Metal acceleration, Darwin VM memory lock, and full edge-to-edge UI.")
        return true
    }

    public func applicationDidReceiveMemoryWarning(_ application: UIApplication) {
        print("[PocketOllama] Kernel memory pressure alert. Triggering RAM scavenger...")
        MemoryScavenger.shared.purgeAndScavengeRAM()
    }
}
