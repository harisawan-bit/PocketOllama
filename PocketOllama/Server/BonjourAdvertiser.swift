import Foundation
import Network

/// Publishes the HTTP endpoint over mDNS so desktop clients can find the phone
/// without typing an IP address.
///
/// Advertises both service types the app declares in NSBonjourServices. Previously
/// only `_ollama._tcp` was published while Info.plist also promised
/// `_openai._tcp`, so one of the two advertised types never resolved.
///
/// A NetServiceDelegate is required: without it, name-registration conflicts and
/// publish failures were completely silent and the .local name simply never
/// resolved with no indication why.
public final class BonjourAdvertiser: NSObject, NetServiceDelegate, @unchecked Sendable {
    public static let shared = BonjourAdvertiser()

    /// The types advertised, matching NSBonjourServices in Info.plist.
    private static let serviceTypes = ["_ollama._tcp.", "_openai._tcp."]

    private var services: [NetService] = []
    private var isBroadcasting: Bool = false
    private let publishLock = NSLock()

    private override init() {
        super.init()
    }

    /// Called when advertising fails, so the UI can say so instead of showing a
    /// .local hostname that will not resolve.
    public var onPublishError: ((String) -> Void)?

    public private(set) var advertisedPort: Int32 = 0
    public private(set) var advertisedName: String = ""

    public func startAdvertising(port: Int32, hostname: String = "iphone-ai") {
        stopAdvertising()
        publishLock.lock()
        defer { publishLock.unlock() }

        advertisedPort = port
        advertisedName = hostname

        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let device = HardwareAutoTuner.shared.detectProfile().marketingName
        let txtRecord: [String: String] = [
            "name": "PocketOllama",
            "version": version,
            "api": "openai-compatible",
            "device": device
        ]
        let txtData = NetService.data(fromTXTRecord: txtRecord.mapValues { $0.data(using: .utf8) ?? Data() })

        var started: [NetService] = []
        for type in Self.serviceTypes {
            let service = NetService(domain: "local.", type: type, name: hostname, port: port)
            service.includesPeerToPeer = true
            service.delegate = self
            service.setTXTRecord(txtData)
            // No .listenForConnections: the NWListener already owns this port and
            // this object never implements didAcceptConnectionWith.
            service.publish()
            started.append(service)
        }
        services = started
        isBroadcasting = true
        print("[Bonjour] Advertising \(started.count) services on port \(port) as \(hostname)")
    }

    public func stopAdvertising() {
        publishLock.lock()
        defer { publishLock.unlock() }
        for service in services {
            service.stop()
            service.delegate = nil
        }
        services.removeAll()
        isBroadcasting = false
    }

    public func isCurrentlyAdvertising() -> Bool {
        publishLock.lock()
        defer { publishLock.unlock() }
        return isBroadcasting
    }

    // MARK: - NetServiceDelegate
    public func netServiceDidPublish(_ sender: NetService) {
        print("[Bonjour] Published \(sender.type) as \(sender.name)")
    }

    public func netService(_ sender: NetService, didNotPublish errorDict: [String: NSNumber]) {
        let code = errorDict[NetService.errorCode]?.intValue ?? -1
        let message = "Bonjour could not advertise \(sender.type) (code \(code)). "
            + "The .local address will not resolve; use the IP address shown instead."
        print("[Bonjour] \(message)")
        DispatchQueue.main.async { self.onPublishError?(message) }
    }

    public func netServiceDidStop(_ sender: NetService) {
        print("[Bonjour] Stopped \(sender.type)")
    }
}
