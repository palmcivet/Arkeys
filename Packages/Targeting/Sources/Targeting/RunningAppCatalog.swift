import Foundation
import AppKit

/// A running app that can be bound as a Arkeys injection target.
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
    private static let iconCacheLock = NSLock()
    private static var iconCache: [String: NSImage] = [:]

    /// Regular user apps with a bundle id, excluding Arkeys and background agents.
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

    /// Resolved icons are cached; misses are not, so a later install can appear.
    public static func icon(forBundleID bundleID: String) -> NSImage? {
        iconCacheLock.lock()
        let cached = iconCache[bundleID]
        iconCacheLock.unlock()
        if let cached {
            return cached
        }

        let resolved: NSImage?
        if let app = runningApplication(bundleID: bundleID), let url = app.bundleURL {
            resolved = NSWorkspace.shared.icon(forFile: url.path)
        } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            resolved = NSWorkspace.shared.icon(forFile: url.path)
        } else {
            resolved = nil
        }

        if let resolved {
            iconCacheLock.lock()
            iconCache[bundleID] = resolved
            iconCacheLock.unlock()
        }
        return resolved
    }

    public static func invalidateCachedIcon(forBundleID bundleID: String) {
        iconCacheLock.lock()
        iconCache.removeValue(forKey: bundleID)
        iconCacheLock.unlock()
    }
}
