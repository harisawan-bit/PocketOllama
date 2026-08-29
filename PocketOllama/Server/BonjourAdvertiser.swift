import Foundation
import Network

public final class BonjourAdvertiser: @unchecked Sendable {
    public static let shared = BonjourAdvertiser()

    private var netService: NetService?
    private var isBroadcasting: Bool = false

    private init() {}

    public func startAdvertising(port: Int32, hostname: String = "iphone-ai") {
        stopAdvertising()

        netService = NetService(domain: "local.", type: "_ollama._tcp.", name: hostname, port: port)
        netService?.includesPeerToPeer = true
        
        let txtDict: [String: String] = [
            "name": "PocketOllama",
            "version": "2.0.0",
            "api": "openai-compatible",
            "device": HardwareAutoTuner.shared.detectProfile().marketingName
        ]
        
        if let txtData = NetService.data(fromTXTRecord: txtDict.mapValues { $0.data(using: .utf8) ?? Data() }) {
            netService?.setTXTRecord(txtData)
        }

        netService?.publish(options: [.listenForConnections])
        isBroadcasting = true
    }

    public func stopAdvertising() {
        if isBroadcasting {
            netService?.stop()
            netService = nil
            isBroadcasting = false
        }
    }
}
