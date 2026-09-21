import AppKit
import Combine

@MainActor
public final class AppUpdateController: ObservableObject {
    @Published public private(set) var isChecking = false

    /// Settings window that hosts update sheets. Weak: the window retains the
    /// tab controller, which retains this object.
    public weak var presentingWindow: NSWindow?

    private let defaults: UserDefaults
    private let now: () -> Date
    private let check: () async -> AppUpdate.Outcome
    private let present: ((AppUpdate.Outcome) -> Void)?
    private var checkTask: Task<AppUpdate.Outcome, Never>?
    private var inFlightPresent: PresentMode = .none

    public convenience init() {
        self.init(
            defaults: .standard,
            now: Date.init,
            check: { await AppUpdate.check() },
            present: nil
        )
    }

    init(
        defaults: UserDefaults,
        now: @escaping () -> Date = Date.init,
        check: @escaping () async -> AppUpdate.Outcome,
        present: ((AppUpdate.Outcome) -> Void)?
    ) {
        self.defaults = defaults
        self.now = now
        self.check = check
        self.present = present
    }

    /// Throttled to once a day. Only surfaces an alert when a newer release exists.
    @discardableResult
    public func checkWhenOpeningSettings() async -> AppUpdate.Outcome? {
        if checkTask == nil {
            guard UpdateCheckPolicy.shouldCheckAutomatically(lastCheck: lastCheckAt, now: now()) else {
                return nil
            }
        }
        return await performCheck(present: .availableOnly)
    }

    /// Always hits the network (or joins an in-flight check) and always presents.
    @discardableResult
    public func checkManually() async -> AppUpdate.Outcome {
        await performCheck(present: .always)
    }

    private func openRelease(_ url: URL) {
        guard GitHubReleaseURL.isTrusted(url) else { return }
        NSWorkspace.shared.open(url)
    }

    private func performCheck(present mode: PresentMode) async -> AppUpdate.Outcome {
        inFlightPresent = max(inFlightPresent, mode)
        if let checkTask {
            return await checkTask.value
        }
        let task = Task { await check() }
        checkTask = task
        isChecking = true
        defer {
            checkTask = nil
            isChecking = false
            inFlightPresent = .none
        }
        let outcome = await task.value
        if outcome != .failed {
            lastCheckAt = now()
        }
        deliver(outcome, mode: inFlightPresent)
        return outcome
    }

    private func deliver(_ outcome: AppUpdate.Outcome, mode: PresentMode) {
        switch mode {
        case .none:
            return
        case .availableOnly:
            guard case .available = outcome else { return }
        case .always:
            break
        }
        if let present {
            present(outcome)
            return
        }
        presentAlert(outcome)
    }

    private func presentAlert(_ outcome: AppUpdate.Outcome) {
        guard let window = presentingWindow, window.isVisible else { return }

        let alert = NSAlert()
        alert.messageText = AppUpdate.alertTitle(outcome)
        if let message = AppUpdate.alertMessage(outcome) {
            alert.informativeText = message
        }

        if case .available(_, let url) = outcome {
            alert.addButton(withTitle: String(localized: "about.update.viewRelease"))
            alert.addButton(withTitle: String(localized: "about.update.later"))
            alert.beginSheetModal(for: window) { [weak self] response in
                if response == .alertFirstButtonReturn {
                    self?.openRelease(url)
                }
            }
        } else {
            alert.addButton(withTitle: String(localized: "common.ok"))
            alert.beginSheetModal(for: window)
        }
    }

    private var lastCheckAt: Date? {
        get { defaults.object(forKey: Keys.lastCheckAt) as? Date }
        set {
            if let newValue {
                defaults.set(newValue, forKey: Keys.lastCheckAt)
            } else {
                defaults.removeObject(forKey: Keys.lastCheckAt)
            }
        }
    }

    private enum PresentMode: Int, Comparable {
        case none = 0
        case availableOnly = 1
        case always = 2

        static func < (lhs: Self, rhs: Self) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    private enum Keys {
        static let lastCheckAt = "updateLastCheckAt"
    }
}
