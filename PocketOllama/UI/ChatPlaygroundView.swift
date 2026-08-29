import SwiftUI

public struct ChatMessage: Identifiable, Sendable {
    public let id = UUID()
    public let role: String
    public var content: String
    public var reasoning: String?
    public var isStreaming: Bool = false
    public var tokensPerSec: Double = 0.0
}

public struct ChatPlaygroundView: View {
    @State private var messages: [ChatMessage] = [
        ChatMessage(
            role: "assistant",
            content: "Hello! I am running locally on your iPhone using Apple Silicon Metal. Ask me anything or test thinking mode!"
        )
    ]
    @State private var inputPrompt: String = ""
    @State private var isGenerating: Bool = false
    @State private var expandedThoughtID: UUID? = nil

    public var body: some View {
        ZStack {
            PocketTheme.bgDeep.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Chat Playground")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundColor(PocketTheme.textPrimary)
                        Text("On-device Metal Inference & Thinking Mode")
                            .font(.system(size: 11))
                            .foregroundColor(PocketTheme.textMuted)
                    }
                    Spacer()
                    Button(action: {
                        messages.removeAll()
                    }) {
                        Image(systemName: "trash")
                            .font(.system(size: 14))
                            .foregroundColor(PocketTheme.textMuted)
                            .padding(8)
                            .background(PocketTheme.bgCard)
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(PocketTheme.bgDeep)

                // Message Stream List
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            ForEach(messages) { msg in
                                MessageBubble(msg: msg, isExpanded: expandedThoughtID == msg.id) {
                                    if expandedThoughtID == msg.id {
                                        expandedThoughtID = nil
                                    } else {
                                        expandedThoughtID = msg.id
                                    }
                                }
                                .id(msg.id)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                    .onChange(of: messages.count) { _ in
                        if let last = messages.last {
                            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                }

                // Input Bar
                HStack(spacing: 12) {
                    TextField("Message local model...", text: $inputPrompt)
                        .font(.system(size: 15))
                        .foregroundColor(PocketTheme.textPrimary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(PocketTheme.bgCard)
                        .cornerRadius(24)
                        .overlay(
                            RoundedRectangle(cornerRadius: 24)
                                .stroke(PocketTheme.borderGlass, lineWidth: 1)
                        )

                    Button(action: sendMessage) {
                        Image(systemName: isGenerating ? "stop.fill" : "arrow.up")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.black)
                            .frame(width: 44, height: 44)
                            .background(inputPrompt.isEmpty && !isGenerating ? PocketTheme.textMuted : PocketTheme.cyan)
                            .clipShape(Circle())
                            .shadow(color: PocketTheme.cyan.opacity(0.3), radius: 6)
                    }
                    .disabled(inputPrompt.isEmpty && !isGenerating)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(PocketTheme.bgDeep)
            }
        }
    }

    private func sendMessage() {
        guard !inputPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let userMsg = ChatMessage(role: "user", content: inputPrompt)
        messages.append(userMsg)
        
        let promptToSend = inputPrompt
        inputPrompt = ""
        isGenerating = true

        var assistantMsg = ChatMessage(role: "assistant", content: "", isStreaming: true)
        let assistantID = assistantMsg.id
        messages.append(assistantMsg)

        Task {
            let stream = await LlamaEngine.shared.streamInference(prompt: promptToSend)
            let start = Date()
            var tokenCount = 0

            do {
                for try await delta in stream {
                    tokenCount += 1
                    if let idx = messages.firstIndex(where: { $0.id == assistantID }) {
                        if let thought = delta.reasoningText {
                            messages[idx].reasoning = (messages[idx].reasoning ?? "") + thought
                            if expandedThoughtID == nil {
                                expandedThoughtID = assistantID
                            }
                        }
                        messages[idx].content += delta.text
                    }
                }
                let duration = Date().timeIntervalSince(start)
                if let idx = messages.firstIndex(where: { $0.id == assistantID }) {
                    messages[idx].isStreaming = false
                    messages[idx].tokensPerSec = (duration > 0) ? Double(tokenCount) / duration : 0
                }
            } catch {
                if let idx = messages.firstIndex(where: { $0.id == assistantID }) {
                    messages[idx].content = "Error during inference: \(error.localizedDescription)"
                    messages[idx].isStreaming = false
                }
            }
            isGenerating = false
        }
    }
}

struct MessageBubble: View {
    let msg: ChatMessage
    let isExpanded: Bool
    let onToggleThought: () -> Void

    var body: some View {
        HStack {
            if msg.role == "user" { Spacer() }

            VStack(alignment: msg.role == "user" ? .trailing : .leading, spacing: 8) {
                // Collapsible Reasoning Accordion
                if let reasoning = msg.reasoning, !reasoning.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Button(action: onToggleThought) {
                            HStack(spacing: 6) {
                                Image(systemName: "brain.head.profile")
                                    .foregroundColor(PocketTheme.purple)
                                Text("Reasoning & Thought Trace")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundColor(PocketTheme.purple)
                                Spacer()
                                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 10))
                                    .foregroundColor(PocketTheme.purple)
                            }
                        }

                        if isExpanded {
                            Text(reasoning)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(PocketTheme.textSecondary)
                                .padding(.top, 4)
                        }
                    }
                    .padding(12)
                    .background(PocketTheme.purple.opacity(0.12))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(PocketTheme.purple.opacity(0.3), lineWidth: 1)
                    )
                }

                // Main Message Content
                if !msg.content.isEmpty {
                    Text(msg.content)
                        .font(.system(size: 15))
                        .foregroundColor(PocketTheme.textPrimary)
                }

                // Live Speed Pill
                if msg.tokensPerSec > 0 {
                    Text(String(format: "%.1f t/s", msg.tokensPerSec))
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(PocketTheme.cyan)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(msg.role == "user" ? PocketTheme.cyan.opacity(0.2) : PocketTheme.bgCard)
            .cornerRadius(18)
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(msg.role == "user" ? PocketTheme.cyan.opacity(0.4) : PocketTheme.borderGlass, lineWidth: 1)
            )

            if msg.role == "assistant" { Spacer() }
        }
    }
}
