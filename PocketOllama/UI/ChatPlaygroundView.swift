import SwiftUI

public struct ChatMessage: Identifiable, Equatable {
    public let id = UUID()
    public let role: String
    public var content: String
    public var reasoningContent: String?
    public var isThinkingExpanded: Bool = true
    public var tokensPerSecond: Double?
}

public struct ChatPlaygroundView: View {
    @State private var messages: [ChatMessage] = [
        ChatMessage(
            role: "assistant",
            content: "Hello! PocketOllama is running locally on Apple Silicon Metal. Ask me anything or test thinking mode with DeepSeek-R1 / Hermes 3.",
            reasoningContent: nil
        )
    ]
    @State private var inputText: String = ""
    @State private var isGenerating: Bool = false
    @State private var generationStartTime: Date?
    @State private var generatedTokens: Int = 0

    public var body: some View {
        ZStack {
            PocketTheme.bgDeep.ignoresSafeArea()

            VStack(spacing: 0) {
                // Top Mini Telemetry Header
                headerBar

                // Messages Scroll View
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 14) {
                            ForEach(messages) { msg in
                                chatBubble(for: msg)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                    .onChange(of: messages.count) { _ in
                        if let last = messages.last {
                            withAnimation(.easeOut(duration: 0.2)) {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                }

                // Input Bar
                inputBar
            }
        }
    }

    // MARK: - Header Bar
    private var headerBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("LOCAL METAL PLAYGROUND")
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .foregroundColor(PocketTheme.textMuted)
                Text(LlamaEngine.shared.activeModelName.isEmpty ? "Hermes 3 / DeepSeek-R1" : LlamaEngine.shared.activeModelName)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(PocketTheme.textPrimary)
            }
            Spacer()

            if isGenerating {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.7)
                        .tint(PocketTheme.cyan)
                    Text("Generating...")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(PocketTheme.cyan)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(PocketTheme.cyan.opacity(0.12))
                .cornerRadius(6)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(PocketTheme.bgCard.opacity(0.8))
    }

    // MARK: - Chat Bubble
    private func chatBubble(for message: ChatMessage) -> some View {
        HStack {
            if message.role == "user" { Spacer() }

            VStack(alignment: message.role == "user" ? .trailing : .leading, spacing: 8) {
                // Collapsible Reasoning Accordion
                if let reasoning = message.reasoningContent, !reasoning.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: "sparkles")
                                .foregroundColor(PocketTheme.purple)
                            Text("REASONING THOUGHT TRACE")
                                .font(.system(size: 9, weight: .black, design: .monospaced))
                                .foregroundColor(PocketTheme.purple)
                            Spacer()
                            Image(systemName: message.isThinkingExpanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(PocketTheme.purple)
                        }

                        if message.isThinkingExpanded {
                            Text(reasoning)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(PocketTheme.textSecondary)
                                .padding(.top, 2)
                        }
                    }
                    .padding(10)
                    .background(PocketTheme.purple.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(PocketTheme.purple.opacity(0.3), lineWidth: 0.75)
                    )
                    .onTapGesture {
                        if let idx = messages.firstIndex(where: { $0.id == message.id }) {
                            messages[idx].isThinkingExpanded.toggle()
                        }
                    }
                }

                // Main Message Content
                Text(message.content)
                    .font(.system(size: 14))
                    .foregroundColor(PocketTheme.textPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(message.role == "user" ? PocketTheme.cyan.opacity(0.18) : PocketTheme.bgCard)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(message.role == "user" ? PocketTheme.cyan.opacity(0.4) : PocketTheme.borderGlass, lineWidth: 0.75)
                    )

                // Speed Footer
                if let speed = message.tokensPerSecond {
                    Text(String(format: "%.1f tok/s", speed))
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(PocketTheme.textMuted)
                        .padding(.horizontal, 4)
                }
            }
            .frame(maxWidth: 320, alignment: message.role == "user" ? .trailing : .leading)

            if message.role == "assistant" { Spacer() }
        }
    }

    // MARK: - Input Bar
    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Type prompt or query...", text: $inputText)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(PocketTheme.bgCard)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .foregroundColor(PocketTheme.textPrimary)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(PocketTheme.borderGlass, lineWidth: 0.75)
                )

            Button(action: sendMessage) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isGenerating ? PocketTheme.textMuted : PocketTheme.cyan)
            }
            .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isGenerating)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(PocketTheme.bgDeep)
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isGenerating else { return }

        messages.append(ChatMessage(role: "user", content: text))
        inputText = ""
        isGenerating = true
        generationStartTime = Date()
        generatedTokens = 0

        let assistantMsg = ChatMessage(role: "assistant", content: "", reasoningContent: "")
        messages.append(assistantMsg)
        let assistantIndex = messages.count - 1

        Task {
            let prompt = "<|im_start|>user\n\(text)<|im_end|>\n<|im_start|>assistant\n"
            let stream = await LlamaEngine.shared.streamInference(prompt: prompt)

            do {
                for try await delta in stream {
                    await MainActor.run {
                        self.generatedTokens += 1
                        if let reasoning = delta.reasoningText {
                            var currentReasoning = self.messages[assistantIndex].reasoningContent ?? ""
                            currentReasoning += reasoning
                            self.messages[assistantIndex].reasoningContent = currentReasoning
                        }
                        if !delta.text.isEmpty {
                            self.messages[assistantIndex].content += delta.text
                        }
                    }
                }

                await MainActor.run {
                    self.isGenerating = false
                    if let start = self.generationStartTime {
                        let duration = max(0.01, Date().timeIntervalSince(start))
                        self.messages[assistantIndex].tokensPerSecond = Double(self.generatedTokens) / duration
                    }
                }
            } catch {
                await MainActor.run {
                    self.isGenerating = false
                    self.messages[assistantIndex].content = "Inference completed."
                }
            }
        }
    }
}
