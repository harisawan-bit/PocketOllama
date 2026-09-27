import Foundation

/// Validation rules for completed model downloads, dependency-free so the CI
/// self-check can compile THIS file rather than a copy that could drift.
public enum DownloaderValidation {
    /// GGUF files begin with the ASCII bytes "GGUF".
    ///
    /// A download can complete successfully and still not be a model: an HTTP 200
    /// carrying an HTML error page or a rate-limit notice was previously saved as
    /// `<model>.gguf` and only failed much later, at load time, with a confusing
    /// error far from the actual cause.
    public static func isGGUF(magic: [UInt8]) -> Bool {
        magic.count >= 4
            && magic[0] == 0x47 && magic[1] == 0x47
            && magic[2] == 0x55 && magic[3] == 0x46
    }

    public static func isGGUF(atPath path: String) -> Bool {
        guard let handle = FileHandle(forReadingAtPath: path) else { return false }
        defer { try? handle.close() }
        guard let magic = try? handle.read(upToCount: 4) else { return false }
        return isGGUF(magic: [UInt8](magic))
    }

    /// A modelId is used directly as a filename, so path separators and traversal
    /// are removed. The ids are internally generated today, but the destination is
    /// a filesystem path and this is a trust boundary.
    public static func safeFileComponent(_ raw: String) -> String {
        var s = raw.replacingOccurrences(of: "/", with: "_")
        s = s.replacingOccurrences(of: "\\", with: "_")
        while s.contains("..") {
            s = s.replacingOccurrences(of: "..", with: "_")
        }
        return s
    }
}
