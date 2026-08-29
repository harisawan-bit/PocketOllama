import SwiftUI

public struct ModelCardData: Identifiable {
    public let id = UUID()
    public let name: String
    public let author: String
    public let sizeText: String
    public let tag: String
    public let downloadURL: String
    public let minRAMGB: Double
}

public struct ModelStoreView: View {
    @State private var downloadedModels: [String] = ["Hermes-3-Llama-3.2-3B.Q4_K_M.gguf"]
    @State private var activeModel: String = "Hermes-3-Llama-3.2-3B.Q4_K_M.gguf"
    @State private var downloadingModelID: UUID? = nil
    @State private var downloadProgress: Double = 0.0

    let curatedHub: [ModelCardData] = [
        ModelCardData(
            name: "Hermes 3 (Llama 3.2 3B)",
            author: "NousResearch",
            sizeText: "2.1 GB",
            tag: "Hermes Agent Optimized",
            downloadURL: "https://huggingface.co/NousResearch/Hermes-3-Llama-3.2-3B-GGUF",
            minRAMGB: 4.0
        ),
        ModelCardData(
            name: "DeepSeek-R1-Distill-1.5B",
            author: "unsloth",
            sizeText: "1.1 GB",
            tag: "Thinking / Reasoning",
            downloadURL: "https://huggingface.co/unsloth/DeepSeek-R1-Distill-Qwen-1.5B-GGUF",
            minRAMGB: 4.0
        ),
        ModelCardData(
            name: "Llama 3.2 1B Instruct",
            author: "bartowski",
            sizeText: "780 MB",
            tag: "Ultra Fast (50+ t/s)",
            downloadURL: "https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF",
            minRAMGB: 3.0
        ),
        ModelCardData(
            name: "Hermes 3 8B (Q4_K_M)",
            author: "NousResearch",
            sizeText: "4.9 GB",
            tag: "High Capability Agent (8GB RAM)",
            downloadURL: "https://huggingface.co/NousResearch/Hermes-3-Llama-3.1-8B-GGUF",
            minRAMGB: 7.5
        )
    ]

    public var body: some View {
        ZStack {
            PocketTheme.bgDeep.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    // Header
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Model Library")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundColor(PocketTheme.textPrimary)
                        Text("GGUF Models for Apple Silicon Metal")
                            .font(.system(size: 13))
                            .foregroundColor(PocketTheme.textMuted)
                    }

                    // Active Model Section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("ACTIVE MODEL IN VRAM")
                            .font(.system(size: 11, weight: .black, design: .monospaced))
                            .foregroundColor(PocketTheme.textMuted)

                        HStack(spacing: 14) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 24))
                                .foregroundColor(PocketTheme.emerald)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(activeModel)
                                    .font(.system(size: 15, weight: .bold, design: .rounded))
                                    .foregroundColor(PocketTheme.textPrimary)
                                Text("Locked in Unified Memory • mlock active")
                                    .font(.system(size: 12))
                                    .foregroundColor(PocketTheme.emerald)
                            }
                            Spacer()
                        }
                        .padding(16)
                        .glassCard(cornerRadius: 18, borderColor: PocketTheme.emerald.opacity(0.4))
                    }

                    // Curated HuggingFace Hub
                    VStack(alignment: .leading, spacing: 14) {
                        Text("CURATED HUGGINGFACE HUB")
                            .font(.system(size: 11, weight: .black, design: .monospaced))
                            .foregroundColor(PocketTheme.textMuted)

                        ForEach(curatedHub) { model in
                            VStack(spacing: 12) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(model.name)
                                            .font(.system(size: 16, weight: .bold, design: .rounded))
                                            .foregroundColor(PocketTheme.textPrimary)
                                        Text("By \(model.author) • \(model.sizeText)")
                                            .font(.system(size: 12))
                                            .foregroundColor(PocketTheme.textSecondary)
                                    }
                                    Spacer()
                                    Text(model.tag)
                                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(PocketTheme.purple.opacity(0.18))
                                        .foregroundColor(PocketTheme.purple)
                                        .cornerRadius(6)
                                }

                                Button(action: {
                                    startDownload(model: model)
                                }) {
                                    HStack {
                                        Image(systemName: "arrow.down.circle.fill")
                                        Text("1-Tap HuggingFace Download")
                                            .font(.system(size: 13, weight: .bold))
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(PocketTheme.cyan.opacity(0.15))
                                    .foregroundColor(PocketTheme.cyan)
                                    .cornerRadius(10)
                                }
                            }
                            .padding(16)
                            .glassCard(cornerRadius: 18)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
        }
    }

    private func startDownload(model: ModelCardData) {
        downloadingModelID = model.id
        downloadProgress = 0.1
    }
}
