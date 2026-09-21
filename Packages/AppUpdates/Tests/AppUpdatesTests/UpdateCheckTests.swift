import XCTest
@testable import AppUpdates

final class UpdateCheckTests: XCTestCase {
    func testNormalizedStripsLeadingVAndWhitespace() {
        XCTAssertEqual(MarketingVersion.normalized("  v0.1.2\n"), "0.1.2")
        XCTAssertEqual(MarketingVersion.normalized("V1.0.0"), "1.0.0")
        XCTAssertEqual(MarketingVersion.normalized("0.1.2"), "0.1.2")
    }

    func testIsNewerUsesNumericCompare() {
        XCTAssertTrue(MarketingVersion.isNewer("v0.1.3", than: "0.1.2"))
        XCTAssertTrue(MarketingVersion.isNewer("0.1.10", than: "0.1.9"))
        XCTAssertFalse(MarketingVersion.isNewer("v0.1.2", than: "0.1.2"))
        XCTAssertFalse(MarketingVersion.isNewer("0.1.2", than: "0.1.3"))
    }

    func testEvaluateAvailableRequiresTrustedURL() {
        let github = URL(string: "https://github.com/palmcivet/Arkeys/releases/tag/v0.1.3")!
        XCTAssertEqual(
            UpdateCheck.evaluate(current: "0.1.2", latestTag: "v0.1.3", releaseURL: github),
            .available(latest: "0.1.3", url: github)
        )

        let other = URL(string: "https://evil.example/download")!
        XCTAssertEqual(
            UpdateCheck.evaluate(current: "0.1.2", latestTag: "v0.1.3", releaseURL: other),
            .failed
        )
    }

    func testEvaluateSameVersionIsUpToDateEvenIfURLIsUntrusted() {
        let other = URL(string: "https://evil.example/download")!
        XCTAssertEqual(
            UpdateCheck.evaluate(current: "0.1.2", latestTag: "v0.1.2", releaseURL: other),
            .upToDate
        )
    }

    func testTrustedReleaseURL() {
        XCTAssertTrue(GitHubReleaseURL.isTrusted(URL(string: "https://github.com/palmcivet/Arkeys/releases/tag/v1")!))
        XCTAssertTrue(GitHubReleaseURL.isTrusted(URL(string: "https://www.github.com/palmcivet/Arkeys/releases/tag/v1")!))
        XCTAssertFalse(GitHubReleaseURL.isTrusted(URL(string: "http://github.com/palmcivet/Arkeys/releases/tag/v1")!))
        XCTAssertFalse(GitHubReleaseURL.isTrusted(URL(string: "https://github.com.evil.example/x")!))
        XCTAssertFalse(GitHubReleaseURL.isTrusted(URL(string: "https://example.com/github.com")!))
    }

    func testShouldCheckAutomaticallyThrottle() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertTrue(UpdateCheckPolicy.shouldCheckAutomatically(lastCheck: nil, now: now))
        XCTAssertFalse(UpdateCheckPolicy.shouldCheckAutomatically(
            lastCheck: now.addingTimeInterval(-3_600),
            now: now
        ))
        XCTAssertTrue(UpdateCheckPolicy.shouldCheckAutomatically(
            lastCheck: now.addingTimeInterval(-(UpdateCheckPolicy.checkInterval + 1)),
            now: now
        ))
    }

    func testReleaseAPIAndBrewCommand() {
        XCTAssertEqual(
            AppUpdate.latestReleaseAPI.absoluteString,
            "https://api.github.com/repos/palmcivet/Arkeys/releases/latest"
        )
        XCTAssertEqual(AppUpdate.brewUpgradeCommand(), "brew upgrade --cask palmcivet/tap/arkeys")
    }

    func testReleaseRequestBypassesLocalCache() {
        let request = AppUpdate.makeURLRequest(url: AppUpdate.latestReleaseAPI)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/vnd.github+json")
        XCTAssertEqual(AppUpdate.urlSession.configuration.requestCachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertEqual(AppUpdate.urlSession.configuration.timeoutIntervalForRequest, 15)
        XCTAssertEqual(AppUpdate.urlSession.configuration.urlCache?.diskCapacity ?? 0, 0)
    }

    func testGitHubReleaseDecoding() throws {
        let json = """
        {"tag_name":"v0.2.0","html_url":"https://github.com/palmcivet/Arkeys/releases/tag/v0.2.0"}
        """.data(using: .utf8)!
        let release = try JSONDecoder().decode(GitHubRelease.self, from: json)
        XCTAssertEqual(release.tagName, "v0.2.0")
        XCTAssertEqual(
            release.htmlURL.absoluteString,
            "https://github.com/palmcivet/Arkeys/releases/tag/v0.2.0"
        )
    }
}
