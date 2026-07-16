import Foundation

/// Metadata for one saved keymap scheme under a target app.
public struct KeymapSchemeMeta: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var updatedAt: Date

    public init(id: UUID = UUID(), name: String, updatedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.updatedAt = updatedAt
    }
}

/// Per-target index of schemes and the active selection.
public struct TargetKeymapManifest: Codable, Hashable, Sendable {
    public var schemes: [KeymapSchemeMeta]
    public var activeSchemeID: UUID?

    public init(schemes: [KeymapSchemeMeta] = [], activeSchemeID: UUID? = nil) {
        self.schemes = schemes
        self.activeSchemeID = activeSchemeID
    }

    public var activeMeta: KeymapSchemeMeta? {
        guard let activeSchemeID else { return schemes.first }
        return schemes.first { $0.id == activeSchemeID } ?? schemes.first
    }
}

/// Persist CanonicalKeymap schemes under Application Support (multi-scheme per target).
public final class KeymapStore: @unchecked Sendable {
    public let directory: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            self.directory = AppSupportPaths.keymapsDirectory()
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    // MARK: - Paths

    public func safeBundleID(_ bundleID: String) -> String {
        bundleID.replacingOccurrences(of: "/", with: "_")
    }

    public func targetDirectory(forBundleID bundleID: String) -> URL {
        directory.appendingPathComponent(safeBundleID(bundleID), isDirectory: true)
    }

    public func manifestURL(forBundleID bundleID: String) -> URL {
        targetDirectory(forBundleID: bundleID).appendingPathComponent("manifest.json")
    }

    public func schemeURL(bundleID: String, schemeID: UUID) -> URL {
        targetDirectory(forBundleID: bundleID).appendingPathComponent("\(schemeID.uuidString).json")
    }

    // MARK: - Manifest

    public func loadManifest(bundleID: String) -> TargetKeymapManifest {
        let url = manifestURL(forBundleID: bundleID)
        guard let data = try? Data(contentsOf: url),
              let manifest = try? decoder.decode(TargetKeymapManifest.self, from: data) else {
            return TargetKeymapManifest()
        }
        return manifest
    }

    public func saveManifest(_ manifest: TargetKeymapManifest, bundleID: String) throws {
        try ensureTargetDirectory(bundleID: bundleID)
        let data = try encoder.encode(manifest)
        try data.write(to: manifestURL(forBundleID: bundleID), options: .atomic)
    }

    public func listSchemes(bundleID: String) -> [KeymapSchemeMeta] {
        loadManifest(bundleID: bundleID).schemes
    }

    public func activeSchemeID(bundleID: String) -> UUID? {
        loadManifest(bundleID: bundleID).activeMeta?.id
    }

    // MARK: - Scheme CRUD

    public func load(bundleID: String, schemeID: UUID) -> CanonicalKeymap? {
        let url = schemeURL(bundleID: bundleID, schemeID: schemeID)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(CanonicalKeymap.self, from: data)
    }

    /// Load the active scheme for a target, if any.
    public func loadActive(bundleID: String) -> (meta: KeymapSchemeMeta, keymap: CanonicalKeymap)? {
        let manifest = loadManifest(bundleID: bundleID)
        guard let meta = manifest.activeMeta,
              let keymap = load(bundleID: bundleID, schemeID: meta.id) else {
            return nil
        }
        return (meta, keymap)
    }

    public func save(_ keymap: CanonicalKeymap, bundleID: String, schemeID: UUID, name: String? = nil) throws {
        try ensureTargetDirectory(bundleID: bundleID)
        var copy = keymap
        if copy.targetHint == nil {
            copy.targetHint = bundleID
        }
        let data = try encoder.encode(copy)
        try data.write(to: schemeURL(bundleID: bundleID, schemeID: schemeID), options: .atomic)

        var manifest = loadManifest(bundleID: bundleID)
        if let idx = manifest.schemes.firstIndex(where: { $0.id == schemeID }) {
            manifest.schemes[idx].updatedAt = Date()
            if let name {
                manifest.schemes[idx].name = name
            }
        } else {
            let meta = KeymapSchemeMeta(id: schemeID, name: name ?? "未命名方案")
            manifest.schemes.append(meta)
            if manifest.activeSchemeID == nil {
                manifest.activeSchemeID = schemeID
            }
        }
        try saveManifest(manifest, bundleID: bundleID)
    }

    /// Create a new scheme, persist it, and make it active.
    @discardableResult
    public func create(
        keymap: CanonicalKeymap,
        bundleID: String,
        name: String
    ) throws -> KeymapSchemeMeta {
        let meta = KeymapSchemeMeta(name: name)
        try save(keymap, bundleID: bundleID, schemeID: meta.id, name: name)
        try setActive(schemeID: meta.id, bundleID: bundleID)
        return meta
    }

    public func setActive(schemeID: UUID, bundleID: String) throws {
        var manifest = loadManifest(bundleID: bundleID)
        guard manifest.schemes.contains(where: { $0.id == schemeID }) else {
            throw KeymapStoreError.schemeNotFound(schemeID)
        }
        manifest.activeSchemeID = schemeID
        try saveManifest(manifest, bundleID: bundleID)
    }

    public func rename(schemeID: UUID, bundleID: String, name: String) throws {
        var manifest = loadManifest(bundleID: bundleID)
        guard let idx = manifest.schemes.firstIndex(where: { $0.id == schemeID }) else {
            throw KeymapStoreError.schemeNotFound(schemeID)
        }
        manifest.schemes[idx].name = name
        manifest.schemes[idx].updatedAt = Date()
        try saveManifest(manifest, bundleID: bundleID)
    }

    public func delete(schemeID: UUID, bundleID: String) throws {
        var manifest = loadManifest(bundleID: bundleID)
        guard manifest.schemes.contains(where: { $0.id == schemeID }) else {
            throw KeymapStoreError.schemeNotFound(schemeID)
        }
        manifest.schemes.removeAll { $0.id == schemeID }
        try? FileManager.default.removeItem(at: schemeURL(bundleID: bundleID, schemeID: schemeID))
        if manifest.activeSchemeID == schemeID {
            manifest.activeSchemeID = manifest.schemes.first?.id
        }
        try saveManifest(manifest, bundleID: bundleID)
    }

    // MARK: - Private

    private func ensureTargetDirectory(bundleID: String) throws {
        try FileManager.default.createDirectory(
            at: targetDirectory(forBundleID: bundleID),
            withIntermediateDirectories: true
        )
    }
}

public enum KeymapStoreError: Error, LocalizedError, Sendable {
    case schemeNotFound(UUID)

    public var errorDescription: String? {
        switch self {
        case .schemeNotFound(let id):
            return "Keymap scheme not found: \(id.uuidString)"
        }
    }
}
