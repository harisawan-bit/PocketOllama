import Foundation
import Combine

public struct DownloadProgress: Sendable {
    public let modelId: String
    public let bytesDownloaded: Int64
    public let totalBytesExpected: Int64
    public let fractionCompleted: Double
    public let speedBytesPerSec: Double
    public let isDownloading: Bool
    public let isCompleted: Bool
    public let errorMessage: String?

    public var formattedProgress: String {
        let currentMB = Double(bytesDownloaded) / (1024.0 * 1024.0)
        let totalMB = Double(totalBytesExpected) / (1024.0 * 1024.0)
        let pct = fractionCompleted * 100.0
        let speedMB = speedBytesPerSec / (1024.0 * 1024.0)
        return String(format: "%.1f%% (%.1f MB / %.1f MB) • %.1f MB/s", pct, currentMB, totalMB, speedMB)
    }
}

public final class ModelDownloader: NSObject, ObservableObject, URLSessionDownloadDelegate, @unchecked Sendable {
    public static let shared = ModelDownloader()

    @Published public private(set) var activeDownloads: [String: DownloadProgress] = [:]
    private var downloadTasks: [String: URLSessionDownloadTask] = [:]
    private var taskToModelId: [Int: String] = [:]
    /// Persisted because iOS relaunches the process to finish a large download.
    /// Without this, the completed file is thrown away on the relaunch.
    private let mapDefaultsKey = "PocketOllama.taskToModelId"

    /// Guards the mutable dictionaries. URLSession delivers delegate callbacks on a
    /// background queue while startDownload/cancelDownload arrive on the caller's,
    /// so these were being mutated concurrently.
    private let lock = NSLock()
    private var lastBytesWritten: [String: (Int64, Date)] = [:]
    private var startedAt: [String: Date] = [:]
    private var session: URLSession!

    private override init() {
        super.init()
        if let stored = UserDefaults.standard.dictionary(forKey: "PocketOllama.taskToModelId") as? [String: String] {
            taskToModelId = stored.compactMapValues { $0 }.reduce(into: [:]) { acc, e in
                if let k = Int(e.key) { acc[k] = e.value }
            }
        }
        let config = URLSessionConfiguration.background(withIdentifier: "com.haris.pocketollama.downloader")
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        self.session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        createModelsDirectoryIfNeeded()
    }

    public func startDownload(modelId: String, urlString: String) {
        guard let url = URL(string: urlString), url.scheme?.hasPrefix("http") == true else {
            publishFailure(modelId: modelId, message: "Invalid download URL")
            return
        }

        // A second tap used to orphan the first task, leaving two tasks writing
        // the same destination file.
        downloadTasks[modelId]?.cancel()

        let task = session.downloadTask(with: url)
        lock.lock()
        downloadTasks[modelId] = task
        taskToModelId[task.taskIdentifier] = modelId
        lastBytesWritten[modelId] = (0, Date())
        startedAt[modelId] = Date()
        persistTaskMapLocked()
        lock.unlock()

        let initialProgress = DownloadProgress(
            modelId: modelId,
            bytesDownloaded: 0,
            totalBytesExpected: 0,
            fractionCompleted: 0.0,
            speedBytesPerSec: 0.0,
            isDownloading: true,
            isCompleted: false,
            errorMessage: nil
        )

        DispatchQueue.main.async {
            self.activeDownloads[modelId] = initialProgress
        }

        task.resume()
        print("[ModelDownloader] Started background download for: \(modelId)")
    }

    /// Drops a finished or failed entry so the row returns to its idle state.
    public func clearDownload(modelId: String) {
        DispatchQueue.main.async {
            self.activeDownloads.removeValue(forKey: modelId)
        }
    }

    public func cancelDownload(modelId: String) {
        lock.lock()
        let task = downloadTasks[modelId]
        if let id = task?.taskIdentifier { taskToModelId.removeValue(forKey: id) }
        downloadTasks.removeValue(forKey: modelId)
        lock.unlock()
        if let task = task {
            task.cancel()
            DispatchQueue.main.async {
                self.activeDownloads.removeValue(forKey: modelId)
            }
        }
    }

    private func publishFailure(modelId: String, message: String) {
        let existing = activeDownloads[modelId]
        DispatchQueue.main.async {
            self.activeDownloads[modelId] = DownloadProgress(
                modelId: modelId,
                bytesDownloaded: existing?.bytesDownloaded ?? 0,
                totalBytesExpected: existing?.totalBytesExpected ?? 0,
                fractionCompleted: existing?.fractionCompleted ?? 0,
                speedBytesPerSec: 0,
                isDownloading: false,
                isCompleted: false,
                errorMessage: message
            )
        }
    }

    // MARK: - URLSessionDownloadDelegate
    public func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        lock.lock()
        let modelId = taskToModelId[downloadTask.taskIdentifier]
        lock.unlock()
        guard let modelId = modelId else { return }

        let now = Date()
        var speed: Double = 0.0
        if let (prevBytes, prevDate) = lastBytesWritten[modelId] {
            let timeElapsed = now.timeIntervalSince(prevDate)
            if timeElapsed >= 0.5 {
                speed = Double(totalBytesWritten - prevBytes) / timeElapsed
                lastBytesWritten[modelId] = (totalBytesWritten, now)
            }
        }

        let fraction = totalBytesExpectedToWrite > 0
            ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            : 0.0

        let progress = DownloadProgress(
            modelId: modelId,
            bytesDownloaded: totalBytesWritten,
            totalBytesExpected: totalBytesExpectedToWrite,
            fractionCompleted: fraction,
            speedBytesPerSec: speed,
            isDownloading: true,
            isCompleted: false,
            errorMessage: nil
        )

        DispatchQueue.main.async {
            self.activeDownloads[modelId] = progress
        }
    }

    /// Without this, a failed or cancelled download left the progress bar stuck.
    public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        lock.lock()
        let resolved = taskToModelId.removeValue(forKey: task.taskIdentifier)
        if let modelId = resolved {
            downloadTasks.removeValue(forKey: modelId)
            lastBytesWritten.removeValue(forKey: modelId)
            startedAt.removeValue(forKey: modelId)
        }
        persistTaskMapLocked()
        lock.unlock()
        guard let modelId = resolved else { return }

        if let error = error as NSError? {
            if error.code == NSURLErrorCancelled { return }   // user tapped cancel
            publishFailure(modelId: modelId, message: error.localizedDescription)
        }
    }

    public func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        lock.lock()
        let modelId = taskToModelId[downloadTask.taskIdentifier]
        lock.unlock()
        guard let modelId = modelId else {
            print("[ModelDownloader] no modelId for finished task \(downloadTask.taskIdentifier)")
            return
        }

        let destDir = getModelsDirectory()
        // modelId became a filename unchecked; a separator here would escape the
        // models directory.
        let safeName = DownloaderValidation.safeFileComponent(modelId)
        let destURL = destDir.appendingPathComponent("\(safeName).gguf")

        let fm = FileManager.default
        do {
            guard DownloaderValidation.isGGUF(atPath: location.path) else {
                publishFailure(modelId: modelId,
                               message: "Downloaded file is not a GGUF model (bad or expired link).")
                return
            }
            if fm.fileExists(atPath: destURL.path) {
                try fm.removeItem(at: destURL)
            }
            try fm.moveItem(at: location, to: destURL)
            print("[ModelDownloader] Successfully saved model to: \(destURL.path)")

            let progress = DownloadProgress(
                modelId: modelId,
                bytesDownloaded: (try? fm.attributesOfItem(atPath: destURL.path)[.size] as? Int64) ?? 0,
                totalBytesExpected: (try? fm.attributesOfItem(atPath: destURL.path)[.size] as? Int64) ?? 0,
                fractionCompleted: 1.0,
                speedBytesPerSec: averageSpeed(modelId: modelId, bytes: (try? fm.attributesOfItem(atPath: destURL.path)[.size] as? Int64) ?? 0),
                isDownloading: false,
                isCompleted: true,
                errorMessage: nil
            )

            DispatchQueue.main.async {
                self.activeDownloads[modelId] = progress
                // Inspect and update recommendations
                let meta = GGUFHeaderParser.shared.inspectGGUF(at: destURL.path)
                ConfigEngine.shared.updateForModel(metadata: meta)
            }
        } catch {
            print("[ModelDownloader] Error moving file: \(error)")
            publishFailure(modelId: modelId, message: "Download finished but could not be saved: \(error.localizedDescription)")
        }
    }

    /// iOS relaunches the app to finish a background download; once the delegate has
    /// drained the events the system must be told it may suspend again.
    public var backgroundCompletionHandler: (() -> Void)? {
        get { _completionHandler }
        set { _completionHandler = newValue }
    }
    private var _completionHandler: (() -> Void)?

    public func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        let handler = _completionHandler
        _completionHandler = nil
        DispatchQueue.main.async { handler?() }
    }

    private func persistTaskMapLocked() {
        UserDefaults.standard.set(
            Dictionary(uniqueKeysWithValues: taskToModelId.map { (String($0.key), $0.value) }),
            forKey: mapDefaultsKey)
    }

    /// Whole-file average, since the last progress callback carried the real one.
    private func averageSpeed(modelId: String, bytes: Int64) -> Double {
        guard let start = startedAt[modelId] else { return 0 }
        let elapsed = Date().timeIntervalSince(start)
        return elapsed > 0 ? Double(bytes) / elapsed : 0
    }

    public func getModelsDirectory() -> URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let modelsDir = paths[0].appendingPathComponent("models")
        createModelsDirectoryIfNeeded()
        return modelsDir
    }

    private func createModelsDirectoryIfNeeded() {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let modelsDir = paths[0].appendingPathComponent("models")
        try? FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true, attributes: nil)
    }
}
