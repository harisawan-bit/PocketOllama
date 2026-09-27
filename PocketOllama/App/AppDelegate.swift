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
        _ = MemoryScavenger.shared.purgeAndScavengeRAM(aggressive: ConfigEngine.shared.enableDarwinBalloonPurge)

        // NOTE: there is deliberately no AVAudioSession here. Activating a
        // .playback session with .duckOthers silenced the user's music every time
        // the app opened, and declaring the audio background mode for an app that
        // plays no audio is an App Review rejection risk. iOS still suspends the
        // app in the background, so overnight inference cannot be promised.

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
        guard !files.isEmpty else { return }

        // Prefer the model the user actually had loaded. Sorting and taking the
        // first one loaded an arbitrary model, so someone using Hermes-3 3B got
        // Qwen 0.5B on the next launch.
        let lastUsed = UserDefaults.standard.string(forKey: "poLastLoadedModel")
        let match = lastUsed.flatMap { wanted in files.first { $0 == wanted } }
        guard let name = match ?? files.first else { return }
        let path = dir.appendingPathComponent(name).path
        do {
            try await LlamaEngine.shared.loadModel(path: path)
            print("[PocketOllama] Restored model on launch: \(name)")
        } catch {
            // A failure here is expected on a device that cannot fit the model.
            print("[PocketOllama] Could not restore \(name): \(error.localizedDescription)")
        }
    }

    /// Without this the system has no way to finish a large download that continued
    /// after the app was suspended, and the app is never told when it may go back to
    /// sleep.
    public func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        ModelDownloader.shared.backgroundCompletionHandler = completionHandler
    }

    public func applicationDidReceiveMemoryWarning(_ application: UIApplication) {
        print("[PocketOllama] Kernel memory pressure alert. Triggering RAM scavenger...")
        MemoryScavenger.shared.purgeAndScavengeRAM(aggressive: ConfigEngine.shared.enableDarwinBalloonPurge)

        // Purging caches does nothing while a multi-gigabyte model is still mapped,
        // so iOS would jetsam the app. Release it instead, unless a generation is
        // in flight, in which case let it finish rather than corrupting the output.
        Task { @MainActor in
            let busy = await LlamaEngine.shared.isBusy
            let loaded = await LlamaEngine.shared.isModelReady
            guard loaded, !busy else { return }
            print("[PocketOllama] Memory pressure: unloading the model to survive.")
            await LlamaEngine.shared.unloadModel()
            UserDefaults.standard.removeObject(forKey: "poLastLoadedModel")
        }
    }
}
