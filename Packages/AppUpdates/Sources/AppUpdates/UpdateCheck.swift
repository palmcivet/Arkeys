import Foundation

/// Pure update-check rules. Networking and alerts live in `AppUpdate` / `AppUpdateController`.
public enum UpdateCheck {
    public enum Outcome: Equatable, Sendable {
        case upToDate
        case available(latest: String, url: URL)
        case failed
    }

    static func evaluate(current: String, latestTag: String, releaseURL: URL) -> Outcome {
        guard MarketingVersion.isNewer(latestTag, than: current) else {
            return .upToDate
        }
        guard GitHubReleaseURL.isTrusted(releaseURL) else {
            return .failed
        }
        return .available(latest: MarketingVersion.normalized(latestTag), url: releaseURL)
    }
}

enum GitHubReleaseURL {
    static func isTrusted(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https" else { return false }
        let host = url.host(percentEncoded: false)?.lowercased()
        return host == "github.com" || host == "www.github.com"
    }
}

enum UpdateCheckPolicy {
    static let checkInterval: TimeInterval = 60 * 60 * 24

    static func shouldCheckAutomatically(lastCheck: Date?, now: Date = Date()) -> Bool {
        guard let lastCheck else { return true }
        return now.timeIntervalSince(lastCheck) >= checkInterval
    }
}
