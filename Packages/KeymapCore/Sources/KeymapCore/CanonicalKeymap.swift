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
}

/// Relative placement inside the target window (origin: top-left).
public struct NormalizedTransform: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    /// Relative control size (PlayCover-style fraction / percent scale).
    public var size: Double

    public init(x: Double, y: Double, size: Double) {
        self.x = x
        self.y = y
        self.size = size
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
    case striker(version: String)
    case unknown(String)

    public var schemeID: KeymapSchemeID {
        switch self {
        case .playCover: return .playCover
        case .muMu: return .muMu
        case .ldPlayer: return .ldPlayer
        case .striker, .unknown: return .playCover
        }
    }
}

public struct CanonicalKeymap: Codable, Hashable, Sendable {
    public var targetHint: String?
    public var source: KeymapSourceMeta
    public var elements: [KeymapElement]

    public init(
        targetHint: String? = nil,
        source: KeymapSourceMeta = .striker(version: "1.0.0"),
        elements: [KeymapElement] = []
    ) {
        self.targetHint = targetHint
        self.source = source
        self.elements = elements
    }

    public var runnableButtons: [ButtonElement] {
        elements.compactMap(\.buttonElement)
    }

    public func button(matchingKeyCode keyCode: UInt16) -> ButtonElement? {
        runnableButtons.first { button in
            if case .virtual(let code) = button.key.code {
                return code == keyCode
            }
            return false
        }
    }

    public var summaryLine: String {
        let buttons = runnableButtons.count
        let others = elements.count - buttons
        let hint = targetHint ?? "(none)"
        return "target=\(hint) buttons=\(buttons) other=\(others) source=\(source)"
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
