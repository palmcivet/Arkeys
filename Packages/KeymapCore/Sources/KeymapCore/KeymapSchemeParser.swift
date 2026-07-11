import Foundation
import UniformTypeIdentifiers

public enum KeymapSchemeID: String, Codable, CaseIterable, Sendable {
    case playCover
    case muMu
    case ldPlayer
}

public enum KeymapParseError: Error, LocalizedError, Sendable {
    case unsupportedScheme(KeymapSchemeID)
    case sniffFailed
    case decodeFailed(String)
    case encodeUnsupported(String)
    case missingParser(KeymapSchemeID)

    public var errorDescription: String? {
        switch self {
        case .unsupportedScheme(let id):
            return "Unsupported keymap scheme: \(id.rawValue)"
        case .sniffFailed:
            return "Could not detect keymap scheme from file"
        case .decodeFailed(let detail):
            return "Failed to decode keymap: \(detail)"
        case .encodeUnsupported(let detail):
            return "Encode not supported: \(detail)"
        case .missingParser(let id):
            return "No parser registered for \(id.rawValue)"
        }
    }
}

/// Pluggable importer/exporter for third-party keymap formats.
public protocol KeymapSchemeParser: Sendable {
    static var schemeID: KeymapSchemeID { get }
    static var displayName: String { get }
    /// File extensions this parser accepts (lowercase, without dot).
    static var importExtensions: Set<String> { get }
    static var importUTTypes: [UTType] { get }

    init()
    static func sniff(data: Data, filename: String?) -> Bool
    func decode(_ data: Data) throws -> CanonicalKeymap
    func encode(_ keymap: CanonicalKeymap) throws -> Data
}

public struct AnyKeymapSchemeParser: Sendable {
    public let schemeID: KeymapSchemeID
    public let displayName: String
    public let importExtensions: Set<String>
    public let importUTTypes: [UTType]
    private let _sniff: @Sendable (Data, String?) -> Bool
    private let _make: @Sendable () -> any KeymapSchemeParser

    public init<P: KeymapSchemeParser>(_ type: P.Type) {
        schemeID = type.schemeID
        displayName = type.displayName
        importExtensions = type.importExtensions
        importUTTypes = type.importUTTypes
        _sniff = { data, filename in type.sniff(data: data, filename: filename) }
        _make = { type.init() }
    }

    public func sniff(data: Data, filename: String?) -> Bool {
        _sniff(data, filename)
    }

    public func make() -> any KeymapSchemeParser {
        _make()
    }
}

public struct KeymapSchemeRegistry: Sendable {
    private let parsers: [AnyKeymapSchemeParser]

    public init(parsers: [AnyKeymapSchemeParser]) {
        self.parsers = parsers
    }

    public init(parserTypes: [any KeymapSchemeParser.Type]) {
        self.parsers = parserTypes.map { AnyKeymapSchemeParser($0) }
    }

    public var availableSchemes: [(id: KeymapSchemeID, name: String)] {
        parsers.map { ($0.schemeID, $0.displayName) }
    }

    public func parser(for scheme: KeymapSchemeID) -> (any KeymapSchemeParser)? {
        parsers.first { $0.schemeID == scheme }?.make()
    }

    public func detect(data: Data, filename: String?) -> (any KeymapSchemeParser)? {
        let ext = filename.flatMap { URL(fileURLWithPath: $0).pathExtension.lowercased() }
        if let ext,
           let match = parsers.first(where: {
               $0.importExtensions.contains(ext) && $0.sniff(data: data, filename: filename)
           }) {
            return match.make()
        }
        return parsers.first { $0.sniff(data: data, filename: filename) }?.make()
    }

    public func importKeymap(data: Data, filename: String?) throws -> CanonicalKeymap {
        guard let parser = detect(data: data, filename: filename) else {
            throw KeymapParseError.sniffFailed
        }
        return try parser.decode(data)
    }

    public func exportKeymap(_ keymap: CanonicalKeymap, scheme: KeymapSchemeID) throws -> Data {
        guard let parser = parser(for: scheme) else {
            throw KeymapParseError.missingParser(scheme)
        }
        return try parser.encode(keymap)
    }
}
