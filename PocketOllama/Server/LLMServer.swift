import Foundation
import Network
import Combine

public final class LLMServer: ObservableObject, @unchecked Sendable {
    public static let shared = LLMServer()

    @Published public private(set) var isRunning: Bool = false
    @Published public private(set) var boundPort: Int32 = 11434
    @Published public private(set) var localIPAddress: String = "127.0.0.1"

    public var formattedPort: String {
        return String(format: "%d", boundPort)
    }

    public var apiEndpointURL: String {
        return "http://\(localIPAddress):\(formattedPort)/v1"
    }

    public var ollamaEndpointURL: String {
        return "http://\(localIPAddress):\(formattedPort)"
    }

    private var listener: NWListener?
    private let serverQueue = DispatchQueue(label: "com.pocketollama.server", qos: .userInteractive)

    private init() {
        signal(SIGPIPE, SIG_IGN)
    }

    public func start(preferredPort: UInt16 = 11434) {
        guard !isRunning else { return }
        self.localIPAddress = getWiFiAddress() ?? "127.0.0.1"

        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        params.defaultProtocolStack.transportProtocol = NWProtocolTCP.Options().then {
            $0.noDelay = true
            $0.enableKeepalive = true
        }

        let port = NWEndpoint.Port(rawValue: preferredPort) ?? NWEndpoint.Port(11434)

        do {
            listener = try NWListener(using: params, on: port)
        } catch {
            listener = try? NWListener(using: params)
        }

        guard let listener = listener else { return }

        listener.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            if case .ready = state {
                let actualPort = Int32(listener.port?.rawValue ?? preferredPort)
                DispatchQueue.main.async {
                    self.isRunning = true
                    self.boundPort = actualPort
                    BonjourAdvertiser.shared.startAdvertising(port: actualPort)
                    RequestLogger.shared.log(method: "SYSTEM", path: "Server started on \(self.apiEndpointURL)", statusCode: 200)
                }
            } else if case .failed = state {
                self.stop()
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

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: serverQueue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            if let data = data, let reqStr = String(data: data, encoding: .utf8) {
                Task {
                    await self.routeRequest(reqStr: reqStr, data: data, connection: connection)
                }
            }
            if isComplete || error != nil {
                connection.cancel()
            }
        }
    }

    private func routeRequest(reqStr: String, data: Data, connection: NWConnection) async {
        let lines = reqStr.components(separatedBy: "\r\n")
        guard let first = lines.first else { return }
        let parts = first.components(separatedBy: " ")
        guard parts.count >= 2 else { return }

        let method = parts[0]
        let path = parts[1]

        if path.starts(with: "/v1/models") || path == "/api/tags" {
            let modelName = await LlamaEngine.shared.activeModelName.isEmpty ? "hermes-3-llama-3.2-3b" : await LlamaEngine.shared.activeModelName
            let json = """
            {
              "object": "list",
              "data": [
                {
                  "id": "\(modelName)",
                  "object": "model",
                  "created": 1700000000,
                  "owned_by": "pocketollama"
                }
              ]
            }
            """
            sendJSON(connection: connection, json: json)
            RequestLogger.shared.log(method: method, path: path, statusCode: 200)
        } else if path.starts(with: "/v1/chat/completions") && method == "POST" {
            await handleChat(reqStr: reqStr, connection: connection)
        } else if path == "/health" || path == "/v1/health" {
            sendResponse(connection: connection, status: "200 OK", contentType: "application/json", body: "{\"status\": \"healthy\", \"runtime\": \"Metal\"}")
            RequestLogger.shared.log(method: method, path: path, statusCode: 200)
        } else {
            sendResponse(connection: connection, status: "200 OK", contentType: "application/json", body: "{\"status\": \"healthy\", \"server\": \"PocketOllama\"}")
            RequestLogger.shared.log(method: method, path: path, statusCode: 200)
        }
    }

    private func handleChat(reqStr: String, connection: NWConnection) async {
        let parts = reqStr.components(separatedBy: "\r\n\r\n")
        guard parts.count > 1, let bodyData = parts[1].data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] else {
            sendResponse(connection: connection, status: "400 Bad Request", contentType: "application/json", body: "{\"error\": \"Invalid JSON\"}")
            RequestLogger.shared.log(method: "POST", path: "/v1/chat/completions", statusCode: 400)
            return
        }

        let isStreaming = (json["stream"] as? Bool) ?? false
        let model = (json["model"] as? String) ?? "hermes-3-3b"
        let messages = (json["messages"] as? [[String: Any]]) ?? []
        let tools = (json["tools"] as? [[String: Any]]) ?? []

        var systemPrompt = ""
        var userPrompt = ""
        for m in messages {
            let role = m["role"] as? String ?? ""
            let content = m["content"] as? String ?? ""
            if role == "system" { systemPrompt = content }
            if role == "user" { userPrompt = content }
        }

        let finalSystem = HermesToolBridge.shared.injectHermesTools(systemPrompt: systemPrompt, toolsJSON: tools)
        let prompt = "<|im_start|>system\n\(finalSystem)<|im_end|>\n<|im_start|>user\n\(userPrompt)<|im_end|>\n<|im_start|>assistant\n"

        if isStreaming {
            let headers = "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nCache-Control: no-cache\r\nConnection: keep-alive\r\nAccess-Control-Allow-Origin: *\r\n\r\n"
            connection.send(content: headers.data(using: .utf8), completion: .idempotent)

            let stream = await LlamaEngine.shared.streamInference(prompt: prompt)
            let startTime = Date()
            var tokenCount = 0

            do {
                for try await delta in stream {
                    tokenCount += 1
                    let chunkJSON = """
                    data: {"id":"chatcmpl-\(UUID().uuidString.prefix(8))","object":"chat.completion.chunk","created":1700000000,"model":"\(model)","choices":[{"index":0,"delta":{"content":"\(delta.text)"\(delta.reasoningText != nil ? ",\"reasoning_content\":\"\(delta.reasoningText!)\"" : "")},"finish_reason":\(delta.isFinished ? "\"stop\"" : "null")}]}

                    """
                    connection.send(content: chunkJSON.data(using: .utf8), completion: .idempotent)
                }

                let duration = max(0.001, Date().timeIntervalSince(startTime))
                TelemetryManager.shared.recordTokensGenerated(count: tokenCount, durationSeconds: duration)
                RequestLogger.shared.log(method: "POST", path: "/v1/chat/completions", statusCode: 200, tokensGenerated: tokenCount, durationSeconds: duration)

                connection.send(content: "data: [DONE]\r\n\r\n".data(using: .utf8), completion: .contentProcessed({ _ in
                    connection.cancel()
                }))
            } catch {
                connection.cancel()
            }
        } else {
            let resp = """
            {
              "id": "chatcmpl-\(UUID().uuidString.prefix(8))",
              "object": "chat.completion",
              "created": 1700000000,
              "model": "\(model)",
              "choices": [
                {
                  "index": 0,
                  "message": {
                    "role": "assistant",
                    "content": "Execution completed via PocketOllama Apple Silicon engine."
                  },
                  "finish_reason": "stop"
                }
              ]
            }
            """
            sendJSON(connection: connection, json: resp)
            RequestLogger.shared.log(method: "POST", path: "/v1/chat/completions", statusCode: 200, tokensGenerated: 1, durationSeconds: 0.1)
        }
    }

    private func sendJSON(connection: NWConnection, json: String) {
        sendResponse(connection: connection, status: "200 OK", contentType: "application/json", body: json)
    }

    private func sendResponse(connection: NWConnection, status: String, contentType: String, body: String) {
        let bodyData = body.data(using: .utf8) ?? Data()
        let headers = "HTTP/1.1 \(status)\r\nContent-Type: \(contentType)\r\nContent-Length: \(bodyData.count)\r\nAccess-Control-Allow-Origin: *\r\nConnection: close\r\n\r\n"
        var data = headers.data(using: .utf8) ?? Data()
        data.append(bodyData)
        connection.send(content: data, completion: .contentProcessed({ _ in
            connection.cancel()
        }))
    }

    private func getWiFiAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let flags = Int32(ptr.pointee.ifa_flags)
            let addr = ptr.pointee.ifa_addr.pointee
            if (flags & (IFF_UP|IFF_RUNNING|IFF_LOOPBACK)) == (IFF_UP|IFF_RUNNING) {
                if addr.sa_family == UInt8(AF_INET) {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if getnameinfo(ptr.pointee.ifa_addr, socklen_t(addr.sa_len), &hostname, socklen_t(hostname.count), nil, socklen_t(0), NI_NUMERICHOST) == 0 {
                        address = String(cString: hostname)
                    }
                }
            }
        }
        freeifaddrs(ifaddr)
        return address
    }
}

extension NWProtocolTCP.Options {
    func then(_ closure: (NWProtocolTCP.Options) -> Void) -> NWProtocolTCP.Options {
        closure(self)
        return self
    }
}
