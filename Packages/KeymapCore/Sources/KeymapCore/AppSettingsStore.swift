import Foundation

/// Persisted user preferences under Application Support/Arkeys/settings.json.
public struct AppSettings: Codable, Hashable, Sendable {
    public var lastTargetBundleID: String?
    public var lastTargetAppName: String?
    public var isEnabled: Bool
    /// Raw value of InjectMode (stored as string to keep KeymapCore free of Injection).
    public var injectModeRaw: String
    public var preferMouseMovedBeforeHID: Bool
    public var restoreCursorAfterHID: Bool
    public var showMenuBarIcon: Bool

    public init(
        lastTargetBundleID: String? = nil,
        lastTargetAppName: String? = nil,
        isEnabled: Bool = true,
        injectModeRaw: String = "cascade",
        preferMouseMovedBeforeHID: Bool = true,
        restoreCursorAfterHID: Bool = true,
        showMenuBarIcon: Bool = true
    ) {
        self.lastTargetBundleID = lastTargetBundleID
        self.lastTargetAppName = lastTargetAppName
        self.isEnabled = isEnabled
        self.injectModeRaw = injectModeRaw
        self.preferMouseMovedBeforeHID = preferMouseMovedBeforeHID
        self.restoreCursorAfterHID = restoreCursorAfterHID
        self.showMenuBarIcon = showMenuBarIcon
    }

    enum CodingKeys: String, CodingKey {
        case lastTargetBundleID
        case lastTargetAppName
        case isEnabled
        case injectModeRaw
        case preferMouseMovedBeforeHID
        case restoreCursorAfterHID
        case showMenuBarIcon
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        lastTargetBundleID = try container.decodeIfPresent(String.self, forKey: .lastTargetBundleID)
        lastTargetAppName = try container.decodeIfPresent(String.self, forKey: .lastTargetAppName)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        injectModeRaw = try container.decodeIfPresent(String.self, forKey: .injectModeRaw) ?? "cascade"
        preferMouseMovedBeforeHID = try container.decodeIfPresent(Bool.self, forKey: .preferMouseMovedBeforeHID) ?? true
        restoreCursorAfterHID = try container.decodeIfPresent(Bool.self, forKey: .restoreCursorAfterHID) ?? true
        showMenuBarIcon = try container.decodeIfPresent(Bool.self, forKey: .showMenuBarIcon) ?? true
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
            self.fileURL = AppSupportPaths.rootDirectory().appendingPathComponent("settings.json")
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
