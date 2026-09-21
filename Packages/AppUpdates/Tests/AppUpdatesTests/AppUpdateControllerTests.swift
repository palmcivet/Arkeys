import XCTest
@testable import AppUpdates

@MainActor
final class AppUpdateControllerTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "AppUpdatesTests.update." + UUID().uuidString
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testSettingsOpenPresentsOnlyWhenAvailable() async {
        let github = URL(string: "https://github.com/palmcivet/Arkeys/releases/tag/v1")!
        let available = AppUpdate.Outcome.available(latest: "1.0.0", url: github)

        let availableProbe = PresentationProbe()
        let availableOutcome = await controller(check: { available }, present: availableProbe.present)
            .checkWhenOpeningSettings()
        XCTAssertEqual(availableOutcome, available)
        XCTAssertEqual(availableProbe.outcomes, [available])

        let currentProbe = PresentationProbe()
        let currentOutcome = await controller(check: { .upToDate }, present: currentProbe.present)
            .checkWhenOpeningSettings()
        XCTAssertEqual(currentOutcome, .upToDate)
        XCTAssertTrue(currentProbe.outcomes.isEmpty)

        let failedProbe = PresentationProbe()
        let failedOutcome = await controller(check: { .failed }, present: failedProbe.present)
            .checkWhenOpeningSettings()
        XCTAssertEqual(failedOutcome, .failed)
        XCTAssertTrue(failedProbe.outcomes.isEmpty)
    }

    func testManualCheckAlwaysPresents() async {
        let probe = PresentationProbe()
        let outcome = await controller(check: { .upToDate }, present: probe.present).checkManually()
        XCTAssertEqual(outcome, .upToDate)
        XCTAssertEqual(probe.outcomes, [.upToDate])
    }

    func testSettingsOpenIsThrottledToOnceADayOnSuccess() async {
        var checks = 0
        var now = Date(timeIntervalSince1970: 1_000_000)
        let controller = AppUpdateController(
            defaults: defaults,
            now: { now },
            check: {
                checks += 1
                return .upToDate
            },
            present: { _ in }
        )

        let first = await controller.checkWhenOpeningSettings()
        let second = await controller.checkWhenOpeningSettings()
        XCTAssertEqual(first, .upToDate)
        XCTAssertNil(second)
        XCTAssertEqual(checks, 1)

        now.addTimeInterval(UpdateCheckPolicy.checkInterval + 1)
        let third = await controller.checkWhenOpeningSettings()
        XCTAssertEqual(third, .upToDate)
        XCTAssertEqual(checks, 2)
    }

    func testFailedCheckDoesNotConsumeDailyQuota() async {
        var checks = 0
        var result = AppUpdate.Outcome.failed
        let controller = AppUpdateController(
            defaults: defaults,
            check: {
                checks += 1
                return result
            },
            present: { _ in }
        )

        let failed = await controller.checkWhenOpeningSettings()
        result = .upToDate
        let retry = await controller.checkWhenOpeningSettings()
        XCTAssertEqual(failed, .failed)
        XCTAssertEqual(retry, .upToDate)
        XCTAssertEqual(checks, 2)
    }

    func testManualCheckRunsEvenWhenAutomaticCheckIsThrottled() async {
        var checks = 0
        let controller = AppUpdateController(
            defaults: defaults,
            check: {
                checks += 1
                return .upToDate
            },
            present: { _ in }
        )

        let automatic = await controller.checkWhenOpeningSettings()
        let manual = await controller.checkManually()
        XCTAssertEqual(automatic, .upToDate)
        XCTAssertEqual(manual, .upToDate)
        XCTAssertEqual(checks, 2)
    }

    func testInFlightChecksAreCoalesced() async {
        var checks = 0
        let probe = PresentationProbe()
        let latch = AsyncLatch()
        let started = expectation(description: "check started")
        let controller = AppUpdateController(
            defaults: defaults,
            check: {
                checks += 1
                started.fulfill()
                await latch.wait()
                return .upToDate
            },
            present: probe.present
        )

        async let first = controller.checkWhenOpeningSettings()
        await fulfillment(of: [started], timeout: 1)
        async let second = controller.checkManually()
        await Task.yield()
        latch.open()

        let outcomes = await (first, second)
        XCTAssertEqual(outcomes.0, .upToDate)
        XCTAssertEqual(outcomes.1, .upToDate)
        XCTAssertEqual(checks, 1)
        XCTAssertEqual(probe.outcomes, [.upToDate])
    }

    private func controller(
        check: @escaping () async -> AppUpdate.Outcome,
        present: @escaping (AppUpdate.Outcome) -> Void
    ) -> AppUpdateController {
        AppUpdateController(
            defaults: UserDefaults(suiteName: UUID().uuidString)!,
            now: Date.init,
            check: check,
            present: present
        )
    }
}

private final class PresentationProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var _outcomes: [AppUpdate.Outcome] = []

    var outcomes: [AppUpdate.Outcome] {
        lock.withLock { _outcomes }
    }

    func present(_ outcome: AppUpdate.Outcome) {
        lock.withLock { _outcomes.append(outcome) }
    }
}

private final class AsyncLatch: @unchecked Sendable {
    private var continuation: CheckedContinuation<Void, Never>?
    private var opened = false
    private let lock = NSLock()

    func wait() async {
        await withCheckedContinuation { cont in
            lock.lock()
            if opened {
                lock.unlock()
                cont.resume()
            } else {
                continuation = cont
                lock.unlock()
            }
        }
    }

    func open() {
        lock.lock()
        opened = true
        let cont = continuation
        continuation = nil
        lock.unlock()
        cont?.resume()
    }
}
