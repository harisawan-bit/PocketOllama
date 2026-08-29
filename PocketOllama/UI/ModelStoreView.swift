import SwiftUI
import UniformTypeIdentifiers

public struct LocalModelItem: Identifiable {
    public let id: String
    public let name: String
    public let sizeDescription: String
    public let parameterSize: String
    public let recommendedContext: String
    public let downloadURL: String?
    public var isDownloaded: Bool
    public var isLoaded: Bool
}

public struct ModelStoreView: View {
    @State private var models: [LocalModelItem] = [
        LocalModelItem(
            id: "deepseek-r1-1.5b",
            name: "DeepSeek-R1-Distill-1.5B (Q4_K_M)",
            sizeDescription: "1.1 GB",
            parameterSize: "1.5 Billion",
            recommendedContext: "Up to 64k Tokens",
            downloadURL: "https://huggingface.co/unsloth/DeepSeek-R1-Distill-Qwen-1.5B-GGUF/resolve/main/DeepSeek-R1-Distill-Qwen-1.5B-Q4_K_M.gguf",
            isDownloaded: true,
            isLoaded: true
        ),
        LocalModelItem(
            id: "qwen2.5-0.5b",
            name: "Qwen 2.5 0.5B Instruct (Q4_K_M)",
            sizeDescription: "390 MB",
            parameterSize: "0.5 Billion",
            recommendedContext: "Up to 128k - 256k Tokens",
            downloadURL: "https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q4_k_m.gguf",
            isDownloaded: false,
            isLoaded: false
        ),
        LocalModelItem(
            id: "hermes-3-3b",
            name: "Hermes 3 Llama-3.2 3B (Q4_K_M)",
            sizeDescription: "2.0 GB",
            parameterSize: "3.2 Billion",
            recommendedContext: "Up to 32k Tokens",
            downloadURL: "https://huggingface.co/NousResearch/Hermes-3-Llama-3.2-3B-GGUF/resolve/main/Hermes-3-Llama-3.2-3B.Q4_K_M.gguf",
            isDownloaded: false,
            isLoaded: false
        ),
        LocalModelItem(
            id: "hermes-3-8b",
            name: "Hermes 3 Llama-3.1 8B (Q4_K_M)",
            sizeDescription: "4.9 GB",
            parameterSize: "8.0 Billion",
            recommendedContext: "Up to 16k Tokens (8GB iPhone)",
            downloadURL: "https://huggingface.co/NousResearch/Hermes-3-Llama-3.1-8B-GGUF/resolve/main/Hermes-3-Llama-3.1-8B.Q4_K_M.gguf",
            isDownloaded: false,
            isLoaded: false
        )
    ]

    @State private var showingFileImporter = false

    public var body: some View {
        ZStack {
            PocketTheme.bgDeep.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    // Header Bar
                    headerBar

                    // Model Cards List
                    ForEach(models) { item in
                        modelCard(for: item)
                    }

                    // Import Custom GGUF Card
                    importCustomGGUFCard
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
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
                print("Import failed: \(err)")
            }
        }
    }

    private var headerBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("MODEL HUB & LOCAL GGUF MANAGER")
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .foregroundColor(PocketTheme.textMuted)
                Text("Pre-Tuned Apple Silicon Models")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(PocketTheme.textPrimary)
            }
            Spacer()
        }
    }

    private func modelCard(for item: LocalModelItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(PocketTheme.textPrimary)
                    HStack(spacing: 8) {
                        Text(item.sizeDescription)
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundColor(PocketTheme.cyan)
                        Text("•")
                            .foregroundColor(PocketTheme.textMuted)
                        Text(item.recommendedContext)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(PocketTheme.emerald)
                    }
                }
                Spacer()

                if item.isLoaded {
                    Text("ACTIVE")
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(PocketTheme.emerald.opacity(0.2))
                        .foregroundColor(PocketTheme.emerald)
                        .cornerRadius(6)
                }
            }

            HStack {
                if item.isDownloaded {
                    Button(action: {
                        loadModel(item)
                    }) {
                        Text(item.isLoaded ? "Reload Engine" : "Load into RAM")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(PocketTheme.cyan.opacity(0.15))
                            .foregroundColor(PocketTheme.cyan)
                            .cornerRadius(8)
                    }
                } else {
                    Button(action: {
                        downloadModel(item)
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.down.circle.fill")
                            Text("Download GGUF")
                        }
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(PocketTheme.purple.opacity(0.2))
                        .foregroundColor(PocketTheme.purple)
                        .cornerRadius(8)
                    }
                }
            }
        }
        .padding(14)
        .fluidGlass(cornerRadius: 16, borderColor: item.isLoaded ? PocketTheme.emerald.opacity(0.3) : PocketTheme.borderGlass)
    }

    private var importCustomGGUFCard: some View {
        Button(action: {
            showingFileImporter = true
        }) {
            HStack(spacing: 12) {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 20))
                    .foregroundColor(PocketTheme.cyan)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Import Custom GGUF File")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(PocketTheme.textPrimary)
                    Text("Select any .gguf file from Files app or iCloud")
                        .font(.system(size: 11))
                        .foregroundColor(PocketTheme.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(PocketTheme.textMuted)
            }
            .padding(14)
            .fluidGlass(cornerRadius: 16)
        }
    }

    private func loadModel(_ item: LocalModelItem) {
        for idx in models.indices {
            models[idx].isLoaded = (models[idx].id == item.id)
        }
        
        let meta = GGUFHeaderParser.shared.inspectGGUF(at: item.id)
        ConfigEngine.shared.updateForModel(metadata: meta)
    }

    private func downloadModel(_ item: LocalModelItem) {
        if let idx = models.firstIndex(where: { $0.id == item.id }) {
            models[idx].isDownloaded = true
            loadModel(models[idx])
        }
    }

    private func importCustomGGUF(url: URL) {
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }

        let fileName = url.lastPathComponent
        let meta = GGUFHeaderParser.shared.inspectGGUF(at: url.path)

        let newItem = LocalModelItem(
            id: url.path,
            name: fileName,
            sizeDescription: "\(meta.fileSizeBytes / (1024*1024)) MB",
            parameterSize: String(format: "%.1fB", meta.estimatedParamCountBillion),
            recommendedContext: "Max \(meta.contextLengthTrained) Tok",
            downloadURL: nil,
            isDownloaded: true,
            isLoaded: true
        )

        models.insert(newItem, at: 0)
        loadModel(newItem)
    }
}
