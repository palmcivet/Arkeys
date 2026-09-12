import Foundation

/// Metadata for one saved keymap scheme under a target app.
public struct KeymapSchemeMeta: Codable, Hashable, Identifiable, Sendable {
    /// Package-level fallback when a caller does not supply a name.
    public static let untitledName = "Untitled"

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
    /// Original bundle id (directory names sanitize `/` to `_`).
    public var bundleID: String?
    /// Cached display name so menus work when the app is not running.
    public var displayName: String?

    public init(
        schemes: [KeymapSchemeMeta] = [],
        activeSchemeID: UUID? = nil,
        bundleID: String? = nil,
        displayName: String? = nil
    ) {
        self.schemes = schemes
        self.activeSchemeID = activeSchemeID
        self.bundleID = bundleID
        self.displayName = displayName
    }

    public var activeMeta: KeymapSchemeMeta? {
        guard let activeSchemeID else { return schemes.first }
        return schemes.first { $0.id == activeSchemeID } ?? schemes.first
    }
}

/// One configured target discovered under the Keymaps directory.
public struct TargetEntry: Hashable, Sendable {
    public let bundleID: String
    public let manifest: TargetKeymapManifest

    public init(bundleID: String, manifest: TargetKeymapManifest) {
        self.bundleID = bundleID
        self.manifest = manifest
    }
}

/// Persist CanonicalKeymap schemes under Application Support (multi-scheme per target).
/// File I/O is synchronous and isolated to the main actor — the same isolation as `InputRuntime`.
@MainActor
public final class KeymapStore {
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
        var manifest = manifest
        manifest.bundleID = bundleID
        let data = try encoder.encode(manifest)
        try data.write(to: manifestURL(forBundleID: bundleID), options: .atomic)
    }

    /// Scan Keymaps/ for every target that has at least one saved scheme.
    public func listAllTargets() -> [TargetEntry] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return contents.compactMap { url -> TargetEntry? in
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory
            if let isDirectory {
                guard isDirectory else { return nil }
            } else {
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
                    return nil
                }
            }
            let folderName = url.lastPathComponent
            let manifest = loadManifest(bundleID: folderName)
            guard !manifest.schemes.isEmpty else { return nil }
            return TargetEntry(bundleID: manifest.bundleID ?? folderName, manifest: manifest)
        }
        .sorted { $0.bundleID.localizedCaseInsensitiveCompare($1.bundleID) == .orderedAscending }
    }

    public func setDisplayName(_ name: String, bundleID: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard FileManager.default.fileExists(atPath: manifestURL(forBundleID: bundleID).path) else { return }
        var manifest = loadManifest(bundleID: bundleID)
        guard manifest.displayName != trimmed else { return }
        manifest.displayName = trimmed
        try? saveManifest(manifest, bundleID: bundleID)
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
            let meta = KeymapSchemeMeta(id: schemeID, name: name ?? KeymapSchemeMeta.untitledName)
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
        if manifest.schemes.isEmpty {
            try deleteTarget(bundleID: bundleID)
            return
        }
        if manifest.activeSchemeID == schemeID {
            manifest.activeSchemeID = manifest.schemes.first?.id
        }
        try saveManifest(manifest, bundleID: bundleID)
    }

    /// Remove every scheme and the target directory.
    public func deleteTarget(bundleID: String) throws {
        let url = targetDirectory(forBundleID: bundleID)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    /// Copy a scheme into another target (new UUID).
    /// If the destination has no active scheme yet (including a brand-new library),
    /// `save` makes this copy active. An existing destination selection is left alone.
    @discardableResult
    public func copyScheme(
        fromBundleID: String,
        schemeID: UUID,
        toBundleID: String,
        name: String? = nil
    ) throws -> KeymapSchemeMeta {
        guard let keymap = load(bundleID: fromBundleID, schemeID: schemeID) else {
            throw KeymapStoreError.schemeNotFound(schemeID)
        }
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = (trimmed?.isEmpty == false ? trimmed : nil)
            ?? loadManifest(bundleID: fromBundleID).schemes.first { $0.id == schemeID }?.name
            ?? KeymapSchemeMeta.untitledName
        var copy = keymap
        copy.targetHint = toBundleID
        let meta = KeymapSchemeMeta(name: resolvedName)
        try save(copy, bundleID: toBundleID, schemeID: meta.id, name: resolvedName)
        return meta
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
