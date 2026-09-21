import Foundation

/// Marketing / GitHub-tag versions (`0.1.2`, `v0.1.2`).
enum MarketingVersion {
    /// Trim whitespace and a single leading `v` / `V`.
    static func normalized(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.first == "v" || text.first == "V" {
            text.removeFirst()
        }
        return text
    }

    /// Numeric component compare after normalization.
    static func isNewer(_ latest: String, than current: String) -> Bool {
        normalized(latest).compare(normalized(current), options: .numeric) == .orderedDescending
    }
}
