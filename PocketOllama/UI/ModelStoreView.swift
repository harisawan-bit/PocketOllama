import SwiftUI
import UniformTypeIdentifiers

public struct LocalModelItem: Identifiable {
    public let id: String
    public let name: String
    public let sizeDescription: String
    public let parameterSize: String
    public let recommendedContext: String
    public let downloadURL: String?
    public var filePath: String?
    public var isDownloaded: Bool
    public var isLoaded: Bool
}

public struct ModelStoreView: View {
    @ObservedObject var downloader = ModelDownloader.shared
    @ObservedObject var config = ConfigEngine.shared

    @State private var models: [LocalModelItem] = [
        LocalModelItem(
            id: "deepseek-r1-1.5b",
            name: "DeepSeek-R1-Distill-1.5B (Q4_K_M)",
            sizeDescription: "1.12 GB",
            parameterSize: "1.5B",
            recommendedContext: "Up to 64k Tokens",
            downloadURL: "https://huggingface.co/unsloth/DeepSeek-R1-Distill-Qwen-1.5B-GGUF/resolve/main/DeepSeek-R1-Distill-Qwen-1.5B-Q4_K_M.gguf",
            filePath: nil,
            isDownloaded: false,
            isLoaded: false
        ),
        LocalModelItem(
            id: "qwen2.5-0.5b",
            name: "Qwen 2.5 0.5B Instruct (Q4_K_M)",
            sizeDescription: "390 MB",
            parameterSize: "0.5B",
            recommendedContext: "Up to 128k - 256k Tokens",
            downloadURL: "https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q4_k_m.gguf",
            filePath: nil,
            isDownloaded: false,
            isLoaded: false
        ),
        LocalModelItem(
            id: "hermes-3-3b",
            name: "Hermes 3 Llama-3.2 3B (Q4_K_M)",
            sizeDescription: "2.01 GB",
            parameterSize: "3.2B",
            recommendedContext: "Up to 32k Tokens",
            downloadURL: "https://huggingface.co/NousResearch/Hermes-3-Llama-3.2-3B-GGUF/resolve/main/Hermes-3-Llama-3.2-3B.Q4_K_M.gguf",
            filePath: nil,
            isDownloaded: false,
            isLoaded: false
        ),
        LocalModelItem(
            id: "hermes-3-8b",
            name: "Hermes 3 Llama-3.1 8B (Q4_K_M)",
            sizeDescription: "4.92 GB",
            parameterSize: "8.0B",
            recommendedContext: "Up to 16k Tokens",
            downloadURL: "https://huggingface.co/NousResearch/Hermes-3-Llama-3.1-8B-GGUF/resolve/main/Hermes-3-Llama-3.1-8B.Q4_K_M.gguf",
            filePath: nil,
            isDownloaded: false,
            isLoaded: false
        )
    ]

    @State private var customModels: [LocalModelItem] = []
    @State private var showingFileImporter = false
    @State private var loadErrorMessage: String? = nil
    @State private var isLoadingModel: Bool = false

    public var body: some View {
        ZStack {
            PocketTheme.bgDeep.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    // Header Bar
                    headerBar

                    if let err = loadErrorMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(PocketTheme.roseAlert)
                            Text(err)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(PocketTheme.roseAlert)
                            Spacer()
                            Button("Dismiss") { loadErrorMessage = nil }
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(PocketTheme.textMuted)
                        }
                        .padding(10)
                        .background(PocketTheme.roseAlert.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }

                    // Preset Models List
                    ForEach(models) { item in
                        modelCard(for: item, isCustom: false)
                    }

                    // Custom Models from Disk
                    if !customModels.isEmpty {
                        HStack {
                            Text("IMPORTED & SIDELOADED MODELS")
                                .font(.system(size: 10, weight: .black, design: .monospaced))
                                .foregroundColor(PocketTheme.textMuted)
                            Spacer()
                        }
                        .padding(.top, 8)
                        .padding(.horizontal, 4)

                        ForEach(customModels) { item in
                            modelCard(for: item, isCustom: true)
                        }
                    }

                    // Import Custom GGUF Card
                    importCustomGGUFCard
                }
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 20)
            }
        }
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [UTType.data],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                importCustomGGUF(url: url)
            case .failure(let err):
                loadErrorMessage = "File import error: \(err.localizedDescription)"
            }
        }
        .onAppear {
            scanModelsOnDisk()
        }
    }

    private var headerBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("LOCAL MODEL REPOSITORY")
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .foregroundColor(PocketTheme.textMuted)
                Text("Zero-Copy GGUF Engine")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(PocketTheme.textPrimary)
            }
            Spacer()

            Button(action: {
                scanModelsOnDisk()
            }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(PocketTheme.devCyan)
                    .padding(6)
                    .background(PocketTheme.bgSurface)
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, 4)
    }

    private func modelCard(for item: LocalModelItem, isCustom: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundColor(PocketTheme.textPrimary)
                    HStack(spacing: 6) {
                        Text(item.sizeDescription)
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(PocketTheme.devCyan)
                        Text("•")
                            .foregroundColor(PocketTheme.textMuted)
                        Text(item.recommendedContext)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(PocketTheme.terminalGreen)
                    }
                }
                Spacer()

                if item.isLoaded {
                    Text("IN-RAM")
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(PocketTheme.terminalGreen.opacity(0.15))
                        .foregroundColor(PocketTheme.terminalGreen)
                        .cornerRadius(4)
                }
            }

            // Download Progress Bar (If actively downloading)
            if let dl = downloader.activeDownloads[item.id], dl.isDownloading {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: dl.fractionCompleted)
                        .tint(PocketTheme.devCyan)

                    HStack {
                        Text(dl.formattedProgress)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(PocketTheme.devCyan)
                        Spacer()
                        Button("Cancel") {
                            downloader.cancelDownload(modelId: item.id)
                        }
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(PocketTheme.roseAlert)
                    }
                }
                .padding(.top, 4)
            } else {
                HStack(spacing: 8) {
                    if item.isDownloaded {
                        Button(action: {
                            loadModel(item)
                        }) {
                            HStack(spacing: 4) {
                                if isLoadingModel && item.isLoaded {
                                    ProgressView().scaleEffect(0.6).tint(PocketTheme.devCyan)
                                }
                                Text(item.isLoaded ? "Active in RAM" : "Load into RAM (<50ms)")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(item.isLoaded ? PocketTheme.terminalGreen.opacity(0.15) : PocketTheme.bgSurfaceHover)
                            .foregroundColor(item.isLoaded ? PocketTheme.terminalGreen : PocketTheme.devCyan)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .stroke(item.isLoaded ? PocketTheme.terminalGreen.opacity(0.4) : PocketTheme.borderSubtle, lineWidth: 1)
                            )
                        }

                        Button(action: {
                            deleteModel(item)
                        }) {
                            Image(systemName: "trash")
                                .font(.system(size: 11))
                                .foregroundColor(PocketTheme.textMuted)
                                .padding(8)
                                .background(PocketTheme.bgSurfaceHover)
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                    } else {
                        Button(action: {
                            if let url = item.downloadURL {
                                downloader.startDownload(modelId: item.id, urlString: url)
                            }
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.down.circle")
                                Text("Download GGUF")
                            }
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(PocketTheme.devCyan.opacity(0.12))
                            .foregroundColor(PocketTheme.devCyan)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .stroke(PocketTheme.devCyan.opacity(0.3), lineWidth: 1)
                            )
                        }
                    }
                }
            }
        }
        .padding(12)
        .devCard(cornerRadius: 8, borderColor: item.isLoaded ? PocketTheme.terminalGreen.opacity(0.4) : PocketTheme.borderSubtle)
    }

    private var importCustomGGUFCard: some View {
        Button(action: {
            showingFileImporter = true
        }) {
            HStack(spacing: 10) {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 16))
                    .foregroundColor(PocketTheme.devCyan)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Import Custom GGUF File")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(PocketTheme.textPrimary)
                    Text("Import from Files, iCloud, or iTunes File Sharing")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(PocketTheme.textMuted)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(PocketTheme.textMuted)
            }
            .padding(12)
            .devCard(cornerRadius: 8)
        }
    }

    private func scanModelsOnDisk() {
        let modelsDir = downloader.getModelsDirectory()
        let fm = FileManager.default

        // 1. Check preset models
        for idx in models.indices {
            let fileURL = modelsDir.appendingPathComponent("\(models[idx].id).gguf")
            let exists = fm.fileExists(atPath: fileURL.path)
            models[idx].isDownloaded = exists
            models[idx].filePath = exists ? fileURL.path : nil
        }

        // 2. Scan for any custom/sideloaded .gguf files in Documents/models and Documents/
        var discovered: [LocalModelItem] = []
        let presetIDs = Set(models.map { "\($0.id).gguf" })

        let scanDirs = [modelsDir, fm.urls(for: .documentDirectory, in: .userDomainMask)[0]]
        for dir in scanDirs {
            if let files = try? fm.contentsOfDirectory(atPath: dir.path) {
                for file in files where file.hasSuffix(".gguf") && !presetIDs.contains(file) {
                    let fullPath = dir.appendingPathComponent(file).path
                    let meta = GGUFHeaderParser.shared.inspectGGUF(at: fullPath)
                    discovered.append(LocalModelItem(
                        id: file,
                        name: file,
                        sizeDescription: "\(meta.fileSizeBytes / (1024*1024)) MB",
                        parameterSize: String(format: "%.1fB", meta.estimatedParamCountBillion),
                        recommendedContext: "Max \(meta.contextLengthTrained) Tok",
                        downloadURL: nil,
                        filePath: fullPath,
                        isDownloaded: true,
                        isLoaded: false
                    ))
                }
            }
        }

        self.customModels = discovered
    }

    private func loadModel(_ item: LocalModelItem) {
        loadErrorMessage = nil
        isLoadingModel = true

        let modelsDir = downloader.getModelsDirectory()
        let path: String
        if let explicitPath = item.filePath, FileManager.default.fileExists(atPath: explicitPath) {
            path = explicitPath
        } else {
            path = modelsDir.appendingPathComponent("\(item.id).gguf").path
        }

        guard FileManager.default.fileExists(atPath: path) else {
            loadErrorMessage = "File not found at: \(path)"
            isLoadingModel = false
            return
        }

        let meta = GGUFHeaderParser.shared.inspectGGUF(at: path)
        config.updateForModel(metadata: meta)

        Task {
            do {
                try await LlamaEngine.shared.loadModel(path: path)
                await MainActor.run {
                    for idx in self.models.indices {
                        self.models[idx].isLoaded = (self.models[idx].id == item.id)
                    }
                    for idx in self.customModels.indices {
                        self.customModels[idx].isLoaded = (self.customModels[idx].id == item.id)
                    }
                    self.isLoadingModel = false
                }
            } catch {
                await MainActor.run {
                    self.loadErrorMessage = "Load Error: \(error.localizedDescription)"
                    self.isLoadingModel = false
                }
            }
        }
    }

    private func deleteModel(_ item: LocalModelItem) {
        let path = item.filePath ?? downloader.getModelsDirectory().appendingPathComponent("\(item.id).gguf").path
        try? FileManager.default.removeItem(atPath: path)
        scanModelsOnDisk()
    }

    private func importCustomGGUF(url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            loadErrorMessage = "Failed to access security-scoped file."
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }

        let fileName = url.lastPathComponent
        let destURL = downloader.getModelsDirectory().appendingPathComponent(fileName)

        do {
            if FileManager.default.fileExists(atPath: destURL.path) {
                try FileManager.default.removeItem(at: destURL)
            }
            try FileManager.default.copyItem(at: url, to: destURL)
            scanModelsOnDisk()

            if let imported = customModels.first(where: { $0.id == fileName }) {
                loadModel(imported)
            }
        } catch {
            loadErrorMessage = "Error copying custom GGUF: \(error.localizedDescription)"
        }
    }
}
