import Foundation

public struct GGUFMetadata: Sendable {
    public let architecture: String
    public let contextLengthTrained: Int
    public let layerCount: Int
    public let embeddingLength: Int
    public let headCountKV: Int
    /// Full attention head count. head_dim is n_embd / head_count, NOT n_embd /
    /// n_head_kv: on grouped-query models the latter overstates the KV cache by the
    /// GQA factor, which made the safe-context estimate far too conservative.
    public let headCount: Int
    public let fileSizeBytes: UInt64
    public let estimatedParamCountBillion: Double
}

public final class GGUFHeaderParser: @unchecked Sendable {
    public static let shared = GGUFHeaderParser()

    private init() {}

    /// Reads the real GGUF header: magic, version, and the metadata keys that matter.
    /// Only the header is read; tensor data is never touched.
    public func inspectGGUF(at path: String) -> GGUFMetadata {
        let fm = FileManager.default
        guard fm.fileExists(atPath: path),
              let attrs = try? fm.attributesOfItem(atPath: path),
              let fileSize = attrs[.size] as? UInt64 else {
            return fallbackMetadata(fileSize: 0)
        }

        guard let handle = FileHandle(forReadingAtPath: path) else {
            return fallbackMetadata(fileSize: fileSize)
        }
        defer { try? handle.close() }

        func read<T: FixedWidthInteger>(_ type: T.Type) -> T? {
            let size = MemoryLayout<T>.size
            guard let data = try? handle.read(upToCount: size), data.count == size else { return nil }
            return data.withUnsafeBytes { $0.loadUnaligned(as: T.self) }
        }

        func readFloat() -> Float? {
            guard let bits = read(UInt32.self) else { return nil }
            return Float(bitPattern: bits)
        }

        func readDouble() -> Double? {
            guard let bits = read(UInt64.self) else { return nil }
            return Double(bitPattern: bits)
        }

        guard let magic = read(UInt32.self) else { return fallbackMetadata(fileSize: fileSize) }
        let ggufMagic: UInt32 = 0x46554747   // "GGUF" little-endian
        guard magic == ggufMagic else { return fallbackMetadata(fileSize: fileSize) }

        _ = read(UInt32.self)              // version
        _ = read(UInt64.self)              // tensor count
        guard let kvCount = read(UInt64.self) else { return fallbackMetadata(fileSize: fileSize) }

        var arch = ""
        var contextLength = 0
        var layers = 0
        var embedDim = 0
        var kvHeads = 0
        var attnHeads = 0

        for _ in 0..<min(kvCount, 16384) {
            guard let keyLen = read(UInt64.self), keyLen <= 512,
                  let keyData = try? handle.read(upToCount: Int(keyLen)), keyData.count == Int(keyLen),
                  let key = String(data: keyData, encoding: .utf8),
                  let valueType = read(UInt32.self) else { break }

            switch valueType {
            case 8:   // STRING
                guard let valLen = read(UInt64.self), valLen <= 512,
                      let valData = try? handle.read(upToCount: Int(valLen)),
                      let value = String(data: valData, encoding: .utf8) else { break }
                if key == "general.architecture" { arch = value }
            case 9:  // UINT32
                let v = Int(read(UInt32.self) ?? 0)
                if key.hasSuffix(".block_count") { layers = v }
                if key.hasSuffix(".context_length") { contextLength = v }
                if key.hasSuffix(".attention.head_count") { attnHeads = v }
                if key.hasSuffix(".embedding_length") { embedDim = v }
                if key.hasSuffix(".attention.head_count_kv") { kvHeads = v }
            case 10: _ = read(Int32.self)
            case 11: _ = read(UInt64.self)
            case 12: _ = read(Int64.self)
            case 13: _ = readFloat()
            case 14: _ = readDouble()
            case 15:  // ARRAY
                guard let arrType = read(UInt32.self), let arrLen = read(UInt64.self) else { break }
                skipArray(handle: handle, elementType: arrType, count: arrLen)
            default:
                break
            }
        }

        guard !arch.isEmpty, layers > 0, embedDim > 0 else {
            return fallbackMetadata(fileSize: fileSize)
        }
        if attnHeads == 0 { attnHeads = max(1, embedDim / 128) }
        if kvHeads == 0 { kvHeads = attnHeads }
        if attnHeads < kvHeads { attnHeads = kvHeads }
        if contextLength == 0 { contextLength = 32768 }

        let params = 12.0 * Double(embedDim) * Double(embedDim) * Double(layers) / 1_000_000_000.0

        return GGUFMetadata(
            architecture: arch,
            contextLengthTrained: contextLength,
            layerCount: layers,
            embeddingLength: embedDim,
            headCountKV: kvHeads,
            headCount: attnHeads,
            fileSizeBytes: fileSize,
            estimatedParamCountBillion: params
        )
    }

    private func skipArray(handle: FileHandle, elementType: UInt32, count: UInt64) {
        // A string array is length-prefixed per element, so it cannot be seeked
        // over. It has to be walked, otherwise the reader stays aligned.
        if elementType == 8 {
            guard count < 200_000 else { return }
            for _ in 0..<count {
                guard let len = try? readU64(handle), len <= 1 << 20 else { return }
                try? handle.seek(toOffset: handle.offsetInFile + len)
            }
            return
        }

        let stride: Int
        switch elementType {
        case 9, 11: stride = 4
        case 10, 12: stride = 4
        case 13: stride = 4
        case 14: stride = 8
        case 15: stride = 0     // nested array
        default: stride = 4
        }
        guard stride > 0, count < 1_000_000 else { return }
        try? handle.seek(toOffset: handle.offsetInFile + UInt64(stride * Int(count)))
    }

    private func readU64(_ handle: FileHandle) -> UInt64? {
        guard let d = try? handle.read(upToCount: 8), d.count == 8 else { return nil }
        return d.withUnsafeBytes { $0.loadUnaligned(as: UInt64.self) }
    }

    /// Calculates KV-cache memory bytes required for a given context token count
    public func calculateKVCacheBytes(
        metadata: GGUFMetadata,
        contextTokens: Int,
        kvQuant: String = "q4_0"
    ) -> UInt64 {
        let bytesPerElement: Double
        switch kvQuant.lowercased() {
        case "q4_0", "q4_1":
            bytesPerElement = 0.5625 // 4.5 bits per weight with scales
        case "q8_0":
            bytesPerElement = 1.0625 // 8.5 bits
        default: // fp16
            bytesPerElement = 2.0
        }

        // KV cache formula: 2 * n_layers * n_kv_heads * (n_embd / n_heads) * bytesPerElement * n_ctx
        let kvHeads = max(1, metadata.headCountKV)
        let headDim = Double(metadata.embeddingLength) / Double(max(1, metadata.headCount))
        let bytesPerToken = 2.0 * Double(metadata.layerCount) * Double(kvHeads) * headDim * bytesPerElement

        return UInt64(Double(contextTokens) * bytesPerToken)
    }

    /// Calculates maximum safe context tokens before hitting iOS process memory limits
    public func calculateMaxSafeContext(
        metadata: GGUFMetadata,
        usableProcessRAMBytes: UInt64,
        kvQuant: String = "q4_0"
    ) -> Int {
        let safetyBuffer: UInt64 = 350 * 1024 * 1024 // 350MB buffer for iOS kernel
        guard usableProcessRAMBytes > (metadata.fileSizeBytes + safetyBuffer) else {
            return 2048
        }

        let availableForKV = usableProcessRAMBytes - metadata.fileSizeBytes - safetyBuffer

        let bytesPerElement: Double = (kvQuant.lowercased() == "q4_0") ? 0.5625 : ((kvQuant.lowercased() == "q8_0") ? 1.0625 : 2.0)
        let kvHeads = max(1, metadata.headCountKV)
        let headDim = Double(metadata.embeddingLength) / Double(max(1, metadata.headCount))
        let bytesPerToken = 2.0 * Double(metadata.layerCount) * Double(kvHeads) * headDim * bytesPerElement

        let maxTokens = Int(Double(availableForKV) / bytesPerToken)

        // Clamp between 2,048 and 262,144 (256k tokens)
        return min(262144, max(2048, (maxTokens / 1024) * 1024))
    }

    private func fallbackMetadata(fileSize: UInt64) -> GGUFMetadata {
        return GGUFMetadata(
            architecture: "llama",
            contextLengthTrained: 32768,
            layerCount: 28,
            embeddingLength: 3072,
            headCountKV: 8,
            headCount: 32,
            fileSizeBytes: fileSize,
            estimatedParamCountBillion: 3.0
        )
    }
}
