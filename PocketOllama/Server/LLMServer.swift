import Foundation
import Network
import Combine

public final class LLMServer: ObservableObject, @unchecked Sendable {
    public static let shared = LLMServer()

    @Published public private(set) var isRunning: Bool = false
    @Published public private(set) var boundPort: Int32 = 11434
    @Published public private(set) var localIPAddress: String = "127.0.0.1"

    public var formattedPort: String { String(format: "%d", boundPort) }
    public var apiEndpointURL: String { "http://\(localIPAddress):\(formattedPort)/v1" }
    public var ollamaEndpointURL: String { "http://\(localIPAddress):\(formattedPort)" }

    private var listener: NWListener?
    private let serverQueue = DispatchQueue(label: "com.pocketollama.server", qos: .userInteractive)
    private let maxRequestBytes = 8 * 1024 * 1024

    private init() {
        signal(SIGPIPE, SIG_IGN)
    }

    /// When set, inference endpoints require `Authorization: Bearer <key>`.
    public static var apiKey: String? = UserDefaults.standard.string(forKey: "poApiKey")

    /// Paths that can drive the model or read model contents.
    private static func requiresAuth(_ path: String) -> Bool {
        path.hasPrefix("/v1/") || path.hasPrefix("/api/")
            || path == "/api/generate" || path == "/api/chat"
    }

    public func start(preferredPort: UInt16 = 11434) {
        guard !isRunning else { return }
        localIPAddress = getWiFiAddress() ?? "127.0.0.1"

        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        params.defaultProtocolStack.transportProtocol = NWProtocolTCP.Options().then {
            $0.noDelay = true
            $0.enableKeepalive = true
        }

        let port = NWEndpoint.Port(rawValue: preferredPort) ?? NWEndpoint.Port(11434)
        listener = (try? NWListener(using: params, on: port)) ?? (try? NWListener(using: params))
        guard let listener else {
            RequestLogger.shared.log(method: "SYSTEM", path: "Failed to bind listener on port \(preferredPort)", statusCode: 500)
            return
        }

        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                let actualPort = Int32(listener.port?.rawValue ?? preferredPort)
                DispatchQueue.main.async {
                    self.isRunning = true
                    self.boundPort = actualPort
                    BonjourAdvertiser.shared.startAdvertising(port: actualPort, hostname: ConfigEngine.shared.serverHostname)
                    RequestLogger.shared.log(method: "SYSTEM", path: "Server listening on \(self.apiEndpointURL)", statusCode: 200)
                }
            case .failed, .cancelled:
                self.stop()
            default:
                break
            }
        }

        listener.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }
        listener.start(queue: serverQueue)
    }

    public func stop() {
        guard isRunning else { return }
        listener?.cancel()
        listener = nil
        BonjourAdvertiser.shared.stopAdvertising()
        DispatchQueue.main.async {
            self.isRunning = false
            RequestLogger.shared.log(method: "SYSTEM", path: "Server stopped", statusCode: 200)
        }
    }

    /// Accumulates the full request before routing. A single TCP read is not a whole request.
    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: serverQueue)

        var buffer = Data()

        func receiveMore() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] chunk, _, isComplete, error in
                guard let self else { return }
                if let chunk, !chunk.isEmpty {
                    buffer.append(chunk)
                    if let request = Self.parseRequest(buffer, maxBytes: self.maxRequestBytes) {
                        Task { await self.route(request, connection: connection) }
                        return
                    }
                    if buffer.count > self.maxRequestBytes {
                        self.sendRaw(connection: connection,
                                     status: "431 Request Header Fields Too Large",
                                     contentType: "application/json",
                                     body: "{\"error\":\"Request too large\"}")
                        return
                    }
                }
                if error != nil {
                    connection.cancel()
                    return
                }
                if isComplete {
                    if let request = Self.parseRequest(buffer, maxBytes: self.maxRequestBytes) {
                        Task { await self.route(request, connection: connection) }
                    } else {
                        connection.cancel()
                    }
                    return
                }
                receiveMore()
            }
        }

        receiveMore()
    }

    private struct HTTPRequest {
        let method: String
        let path: String
        let body: Data
        let authorization: String?
    }

    /// Returns nil until the headers and the full Content-Length body have arrived.
    private static func parseRequest(_ data: Data, maxBytes: Int) -> HTTPRequest? {
        guard let headerEnd = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        guard let headerText = String(data: data[..<headerEnd.lowerBound], encoding: .utf8) else { return nil }

        let lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let parts = requestLine.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard parts.count >= 2 else { return nil }

        var contentLength = 0
        var hasChunked = false
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if name == "content-length" { contentLength = Int(value) ?? 0 }
            if name == "transfer-encoding", value.lowercased().contains("chunked") { hasChunked = true }
        }

        let bodyStart = headerEnd.upperBound
        let available = data.count - bodyStart
        let body: Data

        if hasChunked {
            // Only handle chunked bodies that fully arrived; otherwise keep reading.
            let raw = data[bodyStart...]
            guard let terminator = raw.range(of: Data("0\r\n\r\n".utf8)) else { return nil }
            body = decodeChunked(raw[..<terminator.lowerBound])
        } else {
            guard contentLength >= 0, contentLength <= maxBytes else { return nil }
            guard available >= contentLength else { return nil }
            body = data[bodyStart..<(bodyStart + contentLength)]
        }

        var authorization: String?
        for line in lines.dropFirst() {
            let lower = line.lowercased()
            if lower.hasPrefix("authorization:") {
                authorization = String(line.dropFirst("authorization:".count))
                    .trimmingCharacters(in: .whitespaces)
            }
        }

        return HTTPRequest(method: parts[0].uppercased(), path: parts[1],
                           body: Data(body), authorization: authorization)
    }

    private static func decodeChunked(_ raw: Data) -> Data {
        var out = Data()
        var cursor = raw.startIndex
        while cursor < raw.endIndex {
            guard let lineEnd = raw[cursor...].range(of: Data("\r\n".utf8)) else { break }
            let sizeField = String(data: raw[cursor..<lineEnd.lowerBound], encoding: .utf8) ?? ""
            let size = Int(sizeField.split(separator: ";").first.map(String.init) ?? "", radix: 16) ?? 0
            if size == 0 { break }
            let chunkStart = lineEnd.upperBound
            let chunkEnd = chunkStart + size
            guard chunkEnd <= raw.endIndex else { break }
            out.append(raw[chunkStart..<chunkEnd])
            cursor = chunkEnd + 2
        }
        return out
    }

    private func route(_ request: HTTPRequest, connection: NWConnection?) async {
        let path = request.path
        let method = request.method

        if method == "OPTIONS" {
            sendRaw(connection: connection, status: "204 No Content", contentType: "text/plain", body: "", extraHeaders: corsHeaders)
            RequestLogger.shared.log(method: method, path: path, statusCode: 204)
            return
        }

        // The listener accepts every interface, so inference endpoints require the
        // API key when one is set. Otherwise anyone on the same Wi-Fi could drive
        // the GPU and read the model. Health checks and the dashboard stay open.
        if let key = Self.apiKey, !key.isEmpty, Self.requiresAuth(path) {
            let presented = request.authorization?
                .replacingOccurrences(of: "Bearer ", with: "")
                .trimmingCharacters(in: .whitespaces)
            guard presented == key else {
                sendRaw(connection: connection, status: "401 Unauthorized",
                        contentType: "application/json",
                        body: "{\"error\":\"invalid or missing Authorization: Bearer <key>\"}",
                        extraHeaders: corsHeaders)
                RequestLogger.shared.log(method: method, path: path, statusCode: 401)
                return
            }
        }

        let activeModel = await LlamaEngine.shared.isModelReady
            ? await LlamaEngine.shared.activeModelName
            : "no-model-loaded"

        if (path == "/" || path == "/index.html") && method == "GET" {
            sendRaw(connection: connection, status: "200 OK", contentType: "text/html; charset=utf-8",
                    body: WebDashboardHTML.render(serverIP: localIPAddress, port: formattedPort,
                                              modelName: activeModel, apiKey: Self.apiKey ?? ""))
            RequestLogger.shared.log(method: method, path: path, statusCode: 200)
        } else if path == "/api/version" && method == "GET" {
            sendRaw(connection: connection, status: "200 OK", contentType: "application/json",
                    body: "{\"version\":\"\(Self.appVersion)\"}")
            RequestLogger.shared.log(method: method, path: path, statusCode: 200)
        } else if path == "/v1/models" || path == "/api/tags" {
            let json = modelsJSON(name: activeModel)
            sendRaw(connection: connection, status: "200 OK", contentType: "application/json", body: json)
            RequestLogger.shared.log(method: method, path: path, statusCode: 200)
        } else if (path.hasPrefix("/v1/chat/completions") || path == "/api/chat" || path == "/api/generate") && method == "POST" {
            await handleChat(request, connection: connection)
        } else if path == "/health" || path == "/v1/health" {
            let runtime = await LlamaEngine.shared.isModelReady ? "Metal" : "idle"
            sendRaw(connection: connection, status: "200 OK", contentType: "application/json",
                    body: "{\"status\":\"healthy\",\"runtime\":\"\(runtime)\"}")
            RequestLogger.shared.log(method: method, path: path, statusCode: 200)
        } else {
            sendRaw(connection: connection, status: "404 Not Found", contentType: "application/json",
                    body: "{\"error\":\"Not found\"}")
            RequestLogger.shared.log(method: method, path: path, statusCode: 404)
        }
    }

    /// Lists every GGUF actually present on disk, with real sizes and the loaded one marked.
    /// Real bundle version. /api/version used to hardcode "0.1.48" while the app
    /// shipped 3.1.0, so an Ollama-compatible client was told the wrong version.
    static let appVersion: String = {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }()

    private func modelsJSON(name: String) -> String {
        let dir = ModelDownloader.shared.getModelsDirectory()
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(atPath: dir.path))?
            .filter { $0.hasSuffix(".gguf") }
            .sorted() ?? []

        var entries: [String] = []
        for file in files {
            let size = (try? fm.attributesOfItem(atPath: dir.appendingPathComponent(file).path)[.size] as? Int64) ?? 0
            let id = (file as NSString).deletingPathExtension
            let entry = """
            {"id":"\(id.jsonSafe)","object":"model","created":\(Self.nowEpoch),"owned_by":"pocketollama",
             "name":"\(id.jsonSafe)","model":"\(id.jsonSafe)",
             "modified_at":"2026-01-01T00:00:00Z","size":\(size)}
            """
            entries.append(entry)
        }

        if entries.isEmpty {
            let entry = """
            {"id":"\(name.jsonSafe)","object":"model","created":\(Self.nowEpoch),"owned_by":"pocketollama",
             "name":"\(name.jsonSafe)","model":"\(name.jsonSafe)",
             "modified_at":"2026-01-01T00:00:00Z","size":0}
            """
            entries.append(entry)
        }

        return "{\"object\":\"list\",\"data\":[\(entries.joined(separator: ","))]}"
    }

    private func handleChat(_ request: HTTPRequest, connection: NWConnection?) async {
        let path = request.path

        guard let json = (try? JSONSerialization.jsonObject(with: request.body)) as? [String: Any] else {
            sendRaw(connection: connection, status: "400 Bad Request", contentType: "application/json",
                    body: "{\"error\":{\"message\":\"Invalid JSON body\",\"type\":\"invalid_request_error\"}}")
            RequestLogger.shared.log(method: "POST", path: path, statusCode: 400)
            return
        }

        let isStreaming = (json["stream"] as? Bool) ?? true
        let model = (json["model"] as? String) ?? "pocketollama"
        let messages = (json["messages"] as? [[String: Any]]) ?? []
        let tools = (json["tools"] as? [[String: Any]]) ?? []
        let maxTokens = (json["max_tokens"] as? Int) ?? (json["max_completion_tokens"] as? Int) ?? 1024

        guard !messages.isEmpty || json["prompt"] != nil else {
            sendRaw(connection: connection, status: "400 Bad Request", contentType: "application/json",
                    body: "{\"error\":{\"message\":\"messages or prompt required\",\"type\":\"invalid_request_error\"}}")
            RequestLogger.shared.log(method: "POST", path: path, statusCode: 400)
            return
        }

        guard await LlamaEngine.shared.isModelReady else {
            sendRaw(connection: connection, status: "503 Service Unavailable", contentType: "application/json",
                    body: "{\"error\":{\"message\":\"No model loaded\",\"type\":\"server_error\"}}")
            RequestLogger.shared.log(method: "POST", path: path, statusCode: 503)
            return
        }

        let prompt = buildPrompt(messages: messages, tools: tools, rawPrompt: json["prompt"] as? String)
        let id = "chatcmpl-\(UUID().uuidString.prefix(8))"
        let isOllama = path.hasPrefix("/api")

        var config = InferenceConfig(engine: ConfigEngine.shared)
        config.maxTokens = max(1, min(maxTokens, 4096))

        let stream = await LlamaEngine.shared.streamInference(prompt: prompt, config: config)
        let start = Date()
        let clientIP = RequestLogger.shared.clientIP(for: connection)
        var firstTokenAt: Date?
        var completionText = ""
        var completionReasoning = ""
        var promptTokens = 0
        var toolCalls: [OpenAIToolCall] = []

        if isStreaming {
            let headers = "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nCache-Control: no-cache\r\nConnection: keep-alive\r\nAccess-Control-Allow-Origin: *\r\nAccess-Control-Allow-Headers: Content-Type, Authorization\r\n\r\n"
            if let connection {
                connection.send(content: headers.data(using: .utf8), completion: .idempotent)
            }

            do {
                for try await delta in stream {
                    completionText += delta.text
                    completionReasoning += delta.reasoningText ?? ""

                    if firstTokenAt == nil {
                        firstTokenAt = Date()
                        TelemetryManager.shared.beginMeasurement()
                    } else {
                        TelemetryManager.shared.recordTokenTick()
                    }

                    let chunk: String
                    if isOllama {
                        chunk = "{\"model\":\"\(model.jsonSafe)\",\"message\":{\"role\":\"assistant\",\"content\":\"\(delta.text.jsonSafe)\"},\"done\":\(delta.isFinished)}\n"
                    } else {
                        var fields = ["\"content\":\"\(delta.text.jsonSafe)\""]
                        if let reasoning = delta.reasoningText, !reasoning.isEmpty {
                            fields.append("\"reasoning_content\":\"\(reasoning.jsonSafe)\"")
                        }
                        let finish = delta.isFinished ? "\"stop\"" : "null"
                        chunk = "data: {\"id\":\"\(id)\",\"object\":\"chat.completion.chunk\",\"created\":\(Self.nowEpoch),\"model\":\"\(model.jsonSafe)\",\"choices\":[{\"index\":0,\"delta\":{\(fields.joined(separator: ","))},\"finish_reason\":\(finish)}]}\n\n"
                    }
                    if let connection {
                        connection.send(content: chunk.data(using: .utf8), completion: .idempotent)
                    }
                    if delta.isFinished { break }
                }
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                if let connection {
                    let errChunk = "data: {\"error\":{\"message\":\"\(message.jsonSafe)\",\"type\":\"server_error\"}}\n\n"
                    connection.send(content: errChunk.data(using: .utf8), completion: .idempotent)
                    connection.send(content: "data: [DONE]\r\n\r\n".data(using: .utf8),
                                    completion: .contentProcessed { _ in connection.cancel() })
                }
                RequestLogger.shared.log(method: "POST", path: path, statusCode: 500)
                return
            }

            if path == "/v1/chat/completions" {
                toolCalls = HermesToolBridge.shared.parseStreamingChunk(accumulatedText: completionText).toolCalls
            }

            let usage = await LlamaEngine.shared.lastUsage
            promptTokens = usage.prompt
            // Decode window only, so reported throughput matches the benchmark.
            let decodeStart = firstTokenAt ?? start
            let duration = max(0.001, Date().timeIntervalSince(decodeStart))
            TelemetryManager.shared.recordTokensGenerated(count: usage.completion, durationSeconds: duration)
            RequestLogger.shared.log(method: "POST", path: path, clientIP: clientIP, statusCode: 200,
                                     tokensGenerated: usage.completion, durationSeconds: duration)

            if path == "/v1/chat/completions" {
                if !toolCalls.isEmpty, let connection {
                    let tItems = toolCalls.map { c in
                        "{\"index\":0,\"id\":\"\(c.id)\",\"type\":\"function\",\"function\":{\"name\":\"\(c.function.name.jsonSafe)\",\"arguments\":\"\(c.function.arguments.jsonSafe)\"}}"
                    }.joined(separator: ",")
                    let finalChunk = "data: {\"id\":\"\(id)\",\"object\":\"chat.completion.chunk\",\"created\":\(Self.nowEpoch),\"model\":\"\(model.jsonSafe)\",\"choices\":[{\"index\":0,\"delta\":{\"tool_calls\":[\(tItems)]},\"finish_reason\":\"tool_calls\"}]}\n\n"
                    connection.send(content: finalChunk.data(using: .utf8), completion: .idempotent)
                }
                if let connection {
                    connection.send(content: "data: [DONE]\r\n\r\n".data(using: .utf8), completion: .contentProcessed { _ in
                        connection.cancel()
                    })
                }
            } else {
                connection?.cancel()
            }
        } else {
            do {
                TelemetryManager.shared.beginMeasurement()
                for try await delta in stream {
                    completionText += delta.text
                    completionReasoning += delta.reasoningText ?? ""
                    if firstTokenAt == nil { firstTokenAt = Date() } else { TelemetryManager.shared.recordTokenTick() }
                    if delta.isFinished { break }
                }
            } catch {
                sendRaw(connection: connection, status: "500 Internal Server Error", contentType: "application/json",
                        body: "{\"error\":{\"message\":\"Inference failed\",\"type\":\"server_error\"}}")
                RequestLogger.shared.log(method: "POST", path: path, statusCode: 500)
                return
            }

            let usage = await LlamaEngine.shared.lastUsage
            promptTokens = usage.prompt
            let decodeStart = firstTokenAt ?? start
            let duration = max(0.001, Date().timeIntervalSince(decodeStart))
            TelemetryManager.shared.recordTokensGenerated(count: usage.completion, durationSeconds: duration)

            let body: String
            if isOllama {
                body = """
                {"model":"\(model.jsonSafe)","message":{"role":"assistant","content":"\(completionText.jsonSafe)"},"done":true,
                 "done_reason":"stop","prompt_eval_count":\(promptTokens),"eval_count":\(usage.completion)}
                """
            } else {
                toolCalls = HermesToolBridge.shared.parseStreamingChunk(accumulatedText: completionText).toolCalls
                let toolBlock = toolCalls.isEmpty ? "" : toolCallsJSON(toolCalls)
                let finish = toolCalls.isEmpty ? "stop" : "tool_calls"
                body = """
                {"id":"\(id)","object":"chat.completion","created":\(Self.nowEpoch),"model":"\(model.jsonSafe)",
                 "choices":[{"index":0,"message":{"role":"assistant","content":"\(completionText.jsonSafe)"\(toolBlock)},"finish_reason":"\(finish)"}],
                 "usage":{"prompt_tokens":\(promptTokens),"completion_tokens":\(usage.completion),"total_tokens":\(promptTokens + usage.completion)}}
                """
            }
            sendRaw(connection: connection, status: "200 OK", contentType: "application/json", body: body)
            RequestLogger.shared.log(method: "POST", path: path, clientIP: clientIP, statusCode: 200,
                                     tokensGenerated: usage.completion, durationSeconds: duration)
        }
    }

    private func toolCallsJSON(_ calls: [OpenAIToolCall]) -> String {
        let items = calls.map { call in
            "{\"index\":0,\"id\":\"\(call.id)\",\"type\":\"function\",\"function\":{\"name\":\"\(call.function.name.jsonSafe)\",\"arguments\":\"\(call.function.arguments.jsonSafe)\"}}"
        }
        return ",\"tool_calls\":[\(items.joined(separator: ","))]"
    }

    /// Renders the whole conversation as role-prefixed blocks. LlamaEngine applies the model template.
    private func buildPrompt(messages: [[String: Any]], tools: [[String: Any]], rawPrompt: String?) -> String {
        var blocks: [String] = []

        if !tools.isEmpty {
            blocks.append("system\n" + HermesToolBridge.shared.injectHermesTools(systemPrompt: "", toolsJSON: tools))
        }

        for m in messages {
            let role = (m["role"] as? String ?? "user").lowercased()
            var content = m["content"] as? String ?? ""
            if content.isEmpty, let parts = m["content"] as? [[String: Any]] {
                content = parts.compactMap { $0["text"] as? String }.joined()
            }
            guard !content.isEmpty else { continue }
            let normalized = ["user", "system", "assistant", "tool"].contains(role) ? role : "user"
            blocks.append("\(normalized)\n\(content)")
        }

        if blocks.isEmpty, let rawPrompt, !rawPrompt.isEmpty {
            blocks.append("user\n\(rawPrompt)")
        }

        return blocks.joined(separator: "\n\n")
    }

    /// Real epoch seconds. The old hardcoded constant was fabricated metadata.
    private static var nowEpoch: Int { Int(Date().timeIntervalSince1970) }

    /// Real epoch seconds; the old hardcoded value was fabricated metadata.

    private var corsHeaders: String {
        "Access-Control-Allow-Origin: *\r\nAccess-Control-Allow-Headers: Content-Type, Authorization\r\nAccess-Control-Allow-Methods: POST, GET, OPTIONS\r\n"
    }

    private func sendRaw(connection: NWConnection?, status: String, contentType: String, body: String, extraHeaders: String = "") {
        let bodyData = Data(body.utf8)
        var headers = "HTTP/1.1 \(status)\r\nContent-Type: \(contentType)\r\nContent-Length: \(bodyData.count)\r\n"
        headers += extraHeaders.isEmpty ? "Access-Control-Allow-Origin: *\r\n" : extraHeaders
        headers += "Connection: close\r\n\r\n"
        var payload = Data(headers.utf8)
        payload.append(bodyData)

        guard let connection else { return }
        connection.send(content: payload, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    /// Returns the Wi-Fi IPv4 address, falling back to any other active interface.
    /// en0 is Wi-Fi on iOS; the previous version returned whichever interface happened
    /// to be enumerated last, which could be a VPN or Ethernet tunnel, and it
    /// dereferenced ifa_addr without a nil check.
    private func getWiFiAddress() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        func ipv4(_ ptr: UnsafeMutablePointer<ifaddrs>) -> String? {
            let flags = Int32(ptr.pointee.ifa_flags)
            guard (flags & (IFF_UP | IFF_RUNNING | IFF_LOOPBACK)) == (IFF_UP | IFF_RUNNING),
                  let sa = ptr.pointee.ifa_addr,
                  sa.pointee.sa_family == UInt8(AF_INET) else { return nil }
            var buf = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(sa, socklen_t(sa.pointee.sa_len), &buf, socklen_t(buf.count),
                              nil, socklen_t(0), NI_NUMERICHOST) == 0 else { return nil }
            let ip = String(cString: buf)
            return ip.isEmpty ? nil : ip
        }

        var fallback: String?
        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let name = String(cString: ptr.pointee.ifa_name)
            guard let ip = ipv4(ptr) else { continue }
            if name == "en0" { return ip }
            if fallback == nil { fallback = ip }
        }
        return fallback
    }
}

extension String {
    /// Escapes for embedding in a JSON string literal.
    var jsonSafe: String {
        var out = ""
        out.reserveCapacity(count + 16)
        for ch in unicodeScalars {
            switch ch {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if ch.value < 0x20 {
                    out += String(format: "\\u%04x", ch.value)
                } else {
                    out.unicodeScalars.append(ch)
                }
            }
        }
        return out
    }
}

extension NWProtocolTCP.Options {
    func then(_ closure: (NWProtocolTCP.Options) -> Void) -> NWProtocolTCP.Options {
        closure(self)
        return self
    }
}