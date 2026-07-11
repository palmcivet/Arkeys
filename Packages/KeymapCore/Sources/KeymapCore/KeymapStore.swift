import Foundation

/// Persist CanonicalKeymap as Striker JSON under Application Support.
public final class KeymapStore: @unchecked Sendable {
    public let directory: URL

    public init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            self.directory = base.appendingPathComponent("Striker/Keymaps", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    public func url(forBundleID bundleID: String) -> URL {
        let safe = bundleID.replacingOccurrences(of: "/", with: "_")
        return directory.appendingPathComponent("\(safe).json")
    }

    public func load(bundleID: String) -> CanonicalKeymap? {
        let url = url(forBundleID: bundleID)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(CanonicalKeymap.self, from: data)
    }

    public func save(_ keymap: CanonicalKeymap, bundleID: String) throws {
        var copy = keymap
        if copy.targetHint == nil {
            copy.targetHint = bundleID
        }
        let data = try JSONEncoder().encode(copy)
        try data.write(to: url(forBundleID: bundleID), options: .atomic)
    }

    public func delete(bundleID: String) {
        try? FileManager.default.removeItem(at: url(forBundleID: bundleID))
    }
}
