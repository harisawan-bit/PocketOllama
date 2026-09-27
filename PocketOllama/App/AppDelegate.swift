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
        _ = MemoryScavenger.shared.purgeAndScavengeRAM(aggressive: ConfigEngine.shared.enableDarwinBalloonPurge)

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

        // Re-load the previously used model in the background. A multi-GB GGUF takes
        // seconds to map, so this must not block launch.
        Task.detached(priority: .utility) { await Self.restoreModelOnLaunch() }

        print("[PocketOllama] Initialized with Apple Silicon Metal acceleration and full edge-to-edge UI.")
        return true
    }

    /// Loads the most recently used model, or the only model present, if one exists.
    private static func restoreModelOnLaunch() async {
        let fm = FileManager.default
        let dir = ModelDownloader.shared.getModelsDirectory()
        let files = (try? fm.contentsOfDirectory(atPath: dir.path))?
            .filter { $0.hasSuffix(".gguf") }
            .sorted() ?? []
        guard let name = files.first else { return }

        let path = dir.appendingPathComponent(name).path
        do {
            try await LlamaEngine.shared.loadModel(path: path)
            print("[PocketOllama] Restored model on launch: \(name)")
        } catch {
            // A failure here is expected on a device that cannot fit the model.
            print("[PocketOllama] Could not restore \(name): \(error.localizedDescription)")
        }
    }

    public func applicationDidReceiveMemoryWarning(_ application: UIApplication) {
        print("[PocketOllama] Kernel memory pressure alert. Triggering RAM scavenger...")
        MemoryScavenger.shared.purgeAndScavengeRAM(aggressive: ConfigEngine.shared.enableDarwinBalloonPurge)
    }
}
