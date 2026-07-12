import Foundation

/// Persisted user preferences under Application Support/Striker/settings.json.
public struct AppSettings: Codable, Hashable, Sendable {
    public var lastTargetBundleID: String?
    public var lastTargetAppName: String?
    public var isEnabled: Bool
    /// Raw value of InjectMode (stored as string to keep KeymapCore free of Injection).
    public var injectModeRaw: String
    public var preferMouseMovedBeforeHID: Bool
    public var restoreCursorAfterHID: Bool

    public init(
        lastTargetBundleID: String? = nil,
        lastTargetAppName: String? = nil,
        isEnabled: Bool = true,
        injectModeRaw: String = "postToPid",
        preferMouseMovedBeforeHID: Bool = true,
        restoreCursorAfterHID: Bool = true
    ) {
        self.lastTargetBundleID = lastTargetBundleID
        self.lastTargetAppName = lastTargetAppName
        self.isEnabled = isEnabled
        self.injectModeRaw = injectModeRaw
        self.preferMouseMovedBeforeHID = preferMouseMovedBeforeHID
        self.restoreCursorAfterHID = restoreCursorAfterHID
    }
}

public final class AppSettingsStore: @unchecked Sendable {
    public let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            let dir = base.appendingPathComponent("Striker", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            self.fileURL = dir.appendingPathComponent("settings.json")
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder
        self.decoder = JSONDecoder()
    }

    public func load() -> AppSettings {
        guard let data = try? Data(contentsOf: fileURL),
              let settings = try? decoder.decode(AppSettings.self, from: data) else {
            return AppSettings()
        }
        return settings
    }

    public func save(_ settings: AppSettings) throws {
        let dir = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try encoder.encode(settings)
        try data.write(to: fileURL, options: .atomic)
    }
}
