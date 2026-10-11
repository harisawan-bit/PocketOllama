import Foundation

/// Validation rules for OpenAI-compatible chat requests.
///
/// Dependency-free so the CI self-check compiles THIS file and exercises it,
/// rather than a copy inside the test that could drift from what ships.
public enum RequestValidation {
    /// Model ids are the filenames on disk with the extension removed, so a
    /// slash cannot appear in a legitimate one.
    public static func modelIdIsWellFormed(_ id: String) -> Bool {
        guard !id.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        return !id.contains("/") && !id.contains("\\") && !id.contains("..")
    }

    /// Whether a requested model id matches something the device can serve.
    ///
    /// Comparison is case-insensitive and tolerates the `.gguf` extension, so a
    /// client asking for `Qwen3.5-0.8B-Q4_0.gguf` still resolves. Anything else
    /// is a typo and is rejected rather than silently running the loaded model.
    public static func resolves(requested: String, available: [String]) -> Bool {
        let want = normalise(requested)
        guard !want.isEmpty else { return false }
        return available.contains { normalise($0) == want }
    }

    /// Case- and extension-insensitive comparison key.
    public static func normalise(_ id: String) -> String {
        var s = id.trimmingCharacters(in: .whitespaces)
        if s.lowercased().hasSuffix(".gguf") {
            s = String(s.dropLast(5))
        }
        return s.lowercased()
    }

    /// max_tokens must be a positive number of tokens to generate.
    public static func maxTokensIsValid(_ value: Int?) -> Bool {
        guard let value else { return true }   // omitted means "use the default"
        return value > 0
    }

    /// Clamp a requested generation length to what the context can actually hold.
    /// A client asking for a million tokens gets the real ceiling, not silence.
    public static func clampMaxTokens(_ value: Int?, contextTokens: Int, reserve: Int = 1024) -> Int {
        let requested = value ?? 2048
        let ceiling = max(1, contextTokens - reserve)
        return min(max(1, requested), ceiling)
    }
}
