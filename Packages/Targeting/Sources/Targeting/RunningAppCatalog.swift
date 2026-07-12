import Foundation
import AppKit

/// A running app that can be bound as a Striker injection target.
public struct SelectableApp: Identifiable, Hashable, Sendable {
    public var id: String { bundleIdentifier }
    public let bundleIdentifier: String
    public let name: String
    public let processIdentifier: pid_t

    public init(bundleIdentifier: String, name: String, processIdentifier: pid_t) {
        self.bundleIdentifier = bundleIdentifier
        self.name = name
        self.processIdentifier = processIdentifier
    }
}

public enum RunningAppCatalog {
    /// Regular user apps with a bundle id, excluding Striker and background agents.
    public static func selectableApps(excludingBundleID selfBundleID: String? = Bundle.main.bundleIdentifier) -> [SelectableApp] {
        let apps = NSWorkspace.shared.runningApplications
            .filter { app in
                guard app.activationPolicy == .regular else { return false }
                guard let bundleID = app.bundleIdentifier, !bundleID.isEmpty else { return false }
                if let selfBundleID, bundleID == selfBundleID { return false }
                return true
            }
            .compactMap { app -> SelectableApp? in
                guard let bundleID = app.bundleIdentifier else { return nil }
                return SelectableApp(
                    bundleIdentifier: bundleID,
                    name: app.localizedName ?? bundleID,
                    processIdentifier: app.processIdentifier
                )
            }

        var seen = Set<String>()
        return apps
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .filter { seen.insert($0.bundleIdentifier).inserted }
    }

    public static func runningApplication(bundleID: String) -> NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
    }

    public static func icon(forBundleID bundleID: String) -> NSImage? {
        guard let app = runningApplication(bundleID: bundleID),
              let url = app.bundleURL else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}
