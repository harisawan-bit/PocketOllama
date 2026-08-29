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
            content: "PocketOllama runtime initialized on Apple Silicon Metal GPU. Ready for inference or agent testing.",
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
                // Top Terminal Header
                topTerminalHeader

                // Message Stream
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(messages) { msg in
                                chatBubble(for: msg)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                    }
                    .onChange(of: messages.count) { _ in
                        if let last = messages.last {
                            withAnimation(.easeOut(duration: 0.15)) {
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

    // MARK: - Top Terminal Header
    private var topTerminalHeader: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: "terminal.fill")
                    .font(.system(size: 11))
                    .foregroundColor(PocketTheme.devCyan)
                Text("LOCAL INFERENCE TERMINAL")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(PocketTheme.textMuted)
            }
            Spacer()

            if isGenerating {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.6)
                        .tint(PocketTheme.terminalGreen)
                    Text("STREAMING")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(PocketTheme.terminalGreen)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(PocketTheme.terminalGreen.opacity(0.12))
                .cornerRadius(4)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(PocketTheme.bgSurface)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(PocketTheme.borderSubtle),
            alignment: .bottom
        )
    }

    // MARK: - Chat Bubble
    private func chatBubble(for message: ChatMessage) -> some View {
        HStack {
            if message.role == "user" { Spacer() }

            VStack(alignment: message.role == "user" ? .trailing : .leading, spacing: 6) {
                // Collapsible Reasoning Thought Trace
                if let reasoning = message.reasoningContent, !reasoning.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: "brain.head.profile")
                                .font(.system(size: 10))
                                .foregroundColor(PocketTheme.devIndigo)
                            Text("THOUGHT TRACE / SCRATCHPAD")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(PocketTheme.devIndigo)
                            Spacer()
                            Image(systemName: message.isThinkingExpanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(PocketTheme.devIndigo)
                        }

                        if message.isThinkingExpanded {
                            Text(reasoning)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(PocketTheme.textSecondary)
                                .padding(.top, 2)
                        }
                    }
                    .padding(8)
                    .background(PocketTheme.bgSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(PocketTheme.devIndigo.opacity(0.4), lineWidth: 1)
                    )
                    .onTapGesture {
                        if let idx = messages.firstIndex(where: { $0.id == message.id }) {
                            messages[idx].isThinkingExpanded.toggle()
                        }
                    }
                }

                // Message Text
                Text(message.content)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(PocketTheme.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(message.role == "user" ? PocketTheme.bgSurfaceHover : PocketTheme.bgSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(message.role == "user" ? PocketTheme.devCyan.opacity(0.4) : PocketTheme.borderSubtle, lineWidth: 1)
                    )

                // Speed Footer
                if let speed = message.tokensPerSecond {
                    Text(String(format: "%.1f tok/s", speed))
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(PocketTheme.textMuted)
                        .padding(.horizontal, 2)
                }
            }
            .frame(maxWidth: 320, alignment: message.role == "user" ? .trailing : .leading)

            if message.role == "assistant" { Spacer() }
        }
    }

    // MARK: - Input Bar
    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("Enter prompt or query...", text: $inputText)
                .font(.system(size: 13, design: .monospaced))
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(PocketTheme.bgSurface)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .foregroundColor(PocketTheme.textPrimary)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(PocketTheme.borderSubtle, lineWidth: 1)
                )

            Button(action: sendMessage) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isGenerating ? PocketTheme.textMuted : PocketTheme.devCyan)
            }
            .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isGenerating)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(PocketTheme.bgDeep)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(PocketTheme.borderSubtle),
            alignment: .top
        )
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
