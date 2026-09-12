import Foundation

/// NSEvent/Carbon virtual key code, or special non-keyboard bindings.
public enum KeyCode: Codable, Hashable, Sendable {
    case virtual(UInt16)
    case leftMouse
    case rightMouse
    case middleMouse
    case unknown(Int)

    public var nsEventKeyCode: UInt16? {
        if case .virtual(let code) = self { return code }
        return nil
    }
}

public struct BoundKey: Codable, Hashable, Sendable {
    public var code: KeyCode
    public var name: String

    public init(code: KeyCode, name: String) {
        self.code = code
        self.name = name
    }

    public static func virtual(_ keyCode: UInt16, name: String) -> BoundKey {
        BoundKey(code: .virtual(keyCode), name: name)
    }

    /// Placeholder `?` or an unmapped code that cannot receive a key event.
    public var isUnresolved: Bool {
        switch code {
        case .unknown:
            return true
        case .virtual, .leftMouse, .rightMouse, .middleMouse:
            return name.trimmingCharacters(in: .whitespacesAndNewlines) == "?"
        }
    }
}

/// Relative placement inside the target window (origin: top-left).
public struct NormalizedTransform: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    /// Relative control size in `0…1`. Values `> 1` are treated as percent on ingest.
    public var size: Double

    public init(x: Double, y: Double, size: Double) {
        self.x = x
        self.y = y
        self.size = Self.clampSize(size)
    }

    public static let defaultSize: Double = 0.06
    public static let minSize: Double = 0.015
    public static let maxSize: Double = 0.40

    /// PlayCover sometimes stores percent (`5` = 5%); Arkeys uses `0…1`.
    public static func normalizedSize(_ raw: Double) -> Double {
        raw > 1 ? raw / 100 : raw
    }

    public static func clampSize(_ raw: Double) -> Double {
        min(max(normalizedSize(raw), minSize), maxSize)
    }

    /// Uniform scale from the default keycap. `1` matches the original chrome.
    public static func visualScale(
        size: Double,
        minScale: Double,
        maxScale: Double
    ) -> Double {
        let raw = clampSize(size) / defaultSize
        return min(max(raw, minScale), maxScale)
    }

    private enum CodingKeys: String, CodingKey {
        case x, y, size
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let x = try c.decode(Double.self, forKey: .x)
        let y = try c.decode(Double.self, forKey: .y)
        let size = try c.decode(Double.self, forKey: .size)
        self.init(x: x, y: y, size: size)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(x, forKey: .x)
        try c.encode(y, forKey: .y)
        try c.encode(size, forKey: .size)
    }
}

public struct ButtonElement: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var key: BoundKey
    public var transform: NormalizedTransform

    public init(id: UUID = UUID(), key: BoundKey, transform: NormalizedTransform) {
        self.id = id
        self.key = key
        self.transform = transform
    }
}

public struct JoystickElement: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var up: BoundKey
    public var right: BoundKey
    public var down: BoundKey
    public var left: BoundKey
    public var keyName: String
    public var transform: NormalizedTransform
    public var floating: Bool

    public init(
        id: UUID = UUID(),
        up: BoundKey,
        right: BoundKey,
        down: BoundKey,
        left: BoundKey,
        keyName: String = "Keyboard",
        transform: NormalizedTransform,
        floating: Bool = false
    ) {
        self.id = id
        self.up = up
        self.right = right
        self.down = down
        self.left = left
        self.keyName = keyName
        self.transform = transform
        self.floating = floating
    }
}

public struct MouseAreaElement: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var keyName: String
    public var transform: NormalizedTransform

    public init(id: UUID = UUID(), keyName: String = "Mouse", transform: NormalizedTransform) {
        self.id = id
        self.keyName = keyName
        self.transform = transform
    }
}

public enum KeymapElement: Codable, Identifiable, Hashable, Sendable {
    case button(ButtonElement)
    case draggableButton(ButtonElement)
    case joystick(JoystickElement)
    case mouseArea(MouseAreaElement)

    public var id: UUID {
        switch self {
        case .button(let e), .draggableButton(let e): return e.id
        case .joystick(let e): return e.id
        case .mouseArea(let e): return e.id
        }
    }

    public var isRunnableButton: Bool {
        switch self {
        case .button, .draggableButton: return true
        default: return false
        }
    }

    public var buttonElement: ButtonElement? {
        switch self {
        case .button(let e), .draggableButton(let e): return e
        default: return nil
        }
    }
}

public enum KeymapSourceMeta: Codable, Hashable, Sendable {
    case playCover(version: String)
    case muMu
    case ldPlayer
    case arkeys(version: String)
    case unknown(String)

    public var schemeID: KeymapSchemeID {
        switch self {
        case .playCover: return .playCover
        case .muMu: return .muMu
        case .ldPlayer: return .ldPlayer
        case .arkeys, .unknown: return .playCover
        }
    }
}

public struct CanonicalKeymap: Codable, Hashable, Sendable {
    public var targetHint: String?
    public var source: KeymapSourceMeta
    public var elements: [KeymapElement]

    public init(
        targetHint: String? = nil,
        source: KeymapSourceMeta = .arkeys(version: "1.0.0"),
        elements: [KeymapElement] = []
    ) {
        self.targetHint = targetHint
        self.source = source
        self.elements = elements
    }

    public var runnableButtons: [ButtonElement] {
        elements.compactMap(\.buttonElement)
    }

    public var unresolvedButtonCount: Int {
        runnableButtons.count { $0.key.isUnresolved }
    }

    public func button(matchingKeyCode keyCode: UInt16) -> ButtonElement? {
        runnableButtons.first { button in
            if case .virtual(let code) = button.key.code {
                return code == keyCode
            }
            return false
        }
    }
}

public extension CanonicalKeymap {
    mutating func upsertButton(_ button: ButtonElement) {
        if let idx = elements.firstIndex(where: { $0.id == button.id }) {
            if case .draggableButton = elements[idx] {
                elements[idx] = .draggableButton(button)
            } else {
                elements[idx] = .button(button)
            }
        } else {
            elements.append(.button(button))
        }
    }

    mutating func removeElement(id: UUID) {
        elements.removeAll { $0.id == id }
    }
}
