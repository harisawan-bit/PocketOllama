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
    private var lastBytesWritten: [String: (Int64, Date)] = [:]
    private var session: URLSession!

    private override init() {
        super.init()
        let config = URLSessionConfiguration.background(withIdentifier: "com.haris.pocketollama.downloader")
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        self.session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        createModelsDirectoryIfNeeded()
    }

    public func startDownload(modelId: String, urlString: String) {
        guard let url = URL(string: urlString) else { return }

        let task = session.downloadTask(with: url)
        downloadTasks[modelId] = task
        taskToModelId[task.taskIdentifier] = modelId
        lastBytesWritten[modelId] = (0, Date())

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

    public func cancelDownload(modelId: String) {
        if let task = downloadTasks[modelId] {
            task.cancel()
            downloadTasks.removeValue(forKey: modelId)
            DispatchQueue.main.async {
                self.activeDownloads.removeValue(forKey: modelId)
            }
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
        guard let modelId = taskToModelId[downloadTask.taskIdentifier] else { return }

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

    public func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let modelId = taskToModelId[downloadTask.taskIdentifier] else { return }

        let destDir = getModelsDirectory()
        let destURL = destDir.appendingPathComponent("\(modelId).gguf")

        let fm = FileManager.default
        do {
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
                speedBytesPerSec: 0.0,
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
        }
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
