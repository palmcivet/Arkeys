import Foundation

/// GitHub Releases latest-tag check. No in-app download — open the release
/// page or `brew upgrade`, matching the project's two install paths.
public enum AppUpdate {
    static let githubRepository = "palmcivet/Arkeys"
    static let homebrewCask = "palmcivet/tap/arkeys"

    public typealias Outcome = UpdateCheck.Outcome

    /// Ephemeral so GitHub responses never land in the shared URL cache.
    static let urlSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 15
        return URLSession(configuration: configuration)
    }()

    public static func currentVersion(from bundle: Bundle = .main) -> String? {
        string("CFBundleShortVersionString", from: bundle)
    }

    static func brewUpgradeCommand() -> String {
        "brew upgrade --cask \(homebrewCask)"
    }

    static let latestReleaseAPI = URL(string: "https://api.github.com/repos/\(githubRepository)/releases/latest")!

    static func userAgent(from bundle: Bundle = .main) -> String {
        if let version = currentVersion(from: bundle) {
            return "Arkeys/\(version)"
        }
        return "Arkeys"
    }

    static func makeURLRequest(url: URL, bundle: Bundle = .main) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(userAgent(from: bundle), forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        return request
    }

    static func alertTitle(_ outcome: Outcome) -> String {
        switch outcome {
        case .available: String(localized: "about.update.available.title")
        case .upToDate: String(localized: "about.update.upToDate.title")
        case .failed: String(localized: "about.update.failed.title")
        }
    }

    static func alertMessage(_ outcome: Outcome) -> String? {
        switch outcome {
        case .available(let latest, _):
            let current = currentVersion().map(MarketingVersion.normalized) ?? "—"
            return String(
                format: String(localized: "about.update.available.message"),
                latest,
                current,
                brewUpgradeCommand()
            )
        case .failed:
            return String(localized: "about.update.failed.message")
        case .upToDate:
            return nil
        }
    }

    static func check(
        session: URLSession = urlSession,
        bundle: Bundle = .main
    ) async -> Outcome {
        guard let current = currentVersion(from: bundle) else { return .failed }
        do {
            let (data, response) = try await session.data(for: makeURLRequest(url: latestReleaseAPI, bundle: bundle))
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return .failed
            }

            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            return UpdateCheck.evaluate(
                current: current,
                latestTag: release.tagName,
                releaseURL: release.htmlURL
            )
        } catch {
            return .failed
        }
    }

    private static func string(_ key: String, from bundle: Bundle) -> String? {
        let value = (bundle.object(forInfoDictionaryKey: key) as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (value?.isEmpty == false) ? value : nil
    }
}

struct GitHubRelease: Decodable {
    let tagName: String
    let htmlURL: URL

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
    }
}
