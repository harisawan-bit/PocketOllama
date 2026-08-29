import Foundation

public struct OpenAIToolCall: Codable, Sendable {
    public let id: String
    public let type: String
    public let function: OpenAIFunctionCall
}

public struct OpenAIFunctionCall: Codable, Sendable {
    public let name: String
    public let arguments: String
}

public struct HermesParseResult: Sendable {
    public let contentText: String?
    public let reasoningText: String?
    public let toolCalls: [OpenAIToolCall]
    public let isToolCallInProgress: Bool
}

public final class HermesToolBridge: @unchecked Sendable {
    public static let shared = HermesToolBridge()

    private init() {}

    public func injectHermesTools(systemPrompt: String, toolsJSON: [[String: Any]]) -> String {
        guard !toolsJSON.isEmpty else { return systemPrompt }

        guard let toolsData = try? JSONSerialization.data(withJSONObject: toolsJSON, options: [.prettyPrinted]),
              let toolsString = String(data: toolsData, encoding: .utf8) else {
            return systemPrompt
        }

        let hermesInstructions = """
You are a function calling AI model. You are provided with function signatures within <tools></tools> XML tags. You may call one or more functions to assist with the user query. Don't make assumptions about what values to plug into functions.

Here are the available tools:
<tools>
\(toolsString)
</tools>
"""
        return systemPrompt.isEmpty ? hermesInstructions : "\(systemPrompt)\n\n\(hermesInstructions)"
    }

    public func parseStreamingChunk(accumulatedText: String) -> HermesParseResult {
        var cleanContent = accumulatedText
        var reasoning: String? = nil
        var toolCalls: [OpenAIToolCall] = []
        var inProgress = false

        let thinkPatterns = [
            ("<scratchpad>", "</scratchpad>"),
            ("<thinking>", "</thinking>"),
            ("<plan>", "</plan>"),
            ("<think>", "</think>")
        ]

        for (openTag, closeTag) in thinkPatterns {
            if let startRange = cleanContent.range(of: openTag) {
                if let endRange = cleanContent.range(of: closeTag, range: startRange.upperBound..<cleanContent.endIndex) {
                    let thought = String(cleanContent[startRange.upperBound..<endRange.lowerBound])
                    reasoning = (reasoning == nil) ? thought : "\(reasoning!)\n\(thought)"
                    cleanContent.removeSubrange(startRange.lowerBound..<endRange.upperBound)
                } else {
                    let thought = String(cleanContent[startRange.upperBound...])
                    reasoning = (reasoning == nil) ? thought : "\(reasoning!)\n\(thought)"
                    cleanContent.removeSubrange(startRange.lowerBound...)
                }
            }
        }

        let toolOpenTag = "<tool_call>"
        let toolCloseTag = "</tool_call>"

        while let openRange = cleanContent.range(of: toolOpenTag) {
            if let closeRange = cleanContent.range(of: toolCloseTag, range: openRange.upperBound..<cleanContent.endIndex) {
                let jsonString = String(cleanContent[openRange.upperBound..<closeRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                
                if let jsonData = jsonString.data(using: .utf8),
                   let jsonObject = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                   let name = jsonObject["name"] as? String {
                    
                    let argsObject = jsonObject["arguments"] ?? [:]
                    let argsData = (try? JSONSerialization.data(withJSONObject: argsObject)) ?? Data()
                    let argsString = String(data: argsData, encoding: .utf8) ?? "{}"

                    let toolCall = OpenAIToolCall(
                        id: "call_\(UUID().uuidString.prefix(8))",
                        type: "function",
                        function: OpenAIFunctionCall(name: name, arguments: argsString)
                    )
                    toolCalls.append(toolCall)
                }
                cleanContent.removeSubrange(openRange.lowerBound..<closeRange.upperBound)
            } else {
                inProgress = true
                cleanContent.removeSubrange(openRange.lowerBound...)
                break
            }
        }

        return HermesParseResult(
            contentText: cleanContent.isEmpty ? nil : cleanContent,
            reasoningText: reasoning,
            toolCalls: toolCalls,
            isToolCallInProgress: inProgress
        )
    }
}
