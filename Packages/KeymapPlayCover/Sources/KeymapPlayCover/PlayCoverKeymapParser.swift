import Foundation
import UniformTypeIdentifiers
import KeymapCore

public struct PlayCoverKeymapParser: KeymapSchemeParser {
    public static let schemeID: KeymapSchemeID = .playCover
    public static let displayName = "PlayCover"
    public static let importExtensions: Set<String> = ["plist", "playmap"]
    public static let importUTTypes: [UTType] = [.propertyList]

    public init() {}

    public static func sniff(data: Data, filename: String?) -> Bool {
        let ext = filename.map { URL(fileURLWithPath: $0).pathExtension.lowercased() }
        if let ext, importExtensions.contains(ext) {
            return (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) != nil
                || String(data: data, encoding: .utf8)?.contains("buttonModels") == true
        }
        // Sniff raw plist without extension.
        guard let obj = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            return false
        }
        return obj["buttonModels"] != nil
            || obj["joystickModel"] != nil
            || obj["mouseAreaModel"] != nil
            || obj["bundleIdentifier"] != nil
    }

    public func decode(_ data: Data) throws -> CanonicalKeymap {
        let decoder = PropertyListDecoder()
        let dto: PlayCoverKeymapDTO
        do {
            dto = try decoder.decode(PlayCoverKeymapDTO.self, from: data)
        } catch {
            throw KeymapParseError.decodeFailed(error.localizedDescription)
        }
        return Self.toCanonical(dto)
    }

    public func encode(_ keymap: CanonicalKeymap) throws -> Data {
        let dto = Self.fromCanonical(keymap)
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        do {
            return try encoder.encode(dto)
        } catch {
            throw KeymapParseError.encodeUnsupported(error.localizedDescription)
        }
    }

    static func toCanonical(_ dto: PlayCoverKeymapDTO) -> CanonicalKeymap {
        var elements: [KeymapElement] = []
        elements += dto.buttonModels.map { .button(button(from: $0)) }
        elements += dto.draggableButtonModels.map { .draggableButton(button(from: $0)) }
        elements += dto.joystickModel.map { .joystick(joystick(from: $0)) }
        elements += dto.mouseAreaModel.map { .mouseArea(mouseArea(from: $0)) }
        return CanonicalKeymap(
            targetHint: dto.bundleIdentifier.isEmpty ? nil : dto.bundleIdentifier,
            source: .playCover(version: dto.version),
            elements: elements
        )
    }

    static func fromCanonical(_ keymap: CanonicalKeymap) -> PlayCoverKeymapDTO {
        var buttons: [PlayCoverButtonDTO] = []
        var draggable: [PlayCoverButtonDTO] = []
        var joysticks: [PlayCoverJoystickDTO] = []
        var mice: [PlayCoverMouseAreaDTO] = []

        for element in keymap.elements {
            switch element {
            case .button(let b):
                buttons.append(dto(from: b))
            case .draggableButton(let b):
                draggable.append(dto(from: b))
            case .joystick(let j):
                joysticks.append(dto(from: j))
            case .mouseArea(let m):
                mice.append(PlayCoverMouseAreaDTO(
                    keyName: m.keyName,
                    transform: dto(from: m.transform)
                ))
            }
        }

        let version: String
        if case .playCover(let v) = keymap.source {
            version = v
        } else {
            version = "2.0.0"
        }

        return PlayCoverKeymapDTO(
            buttonModels: buttons,
            draggableButtonModels: draggable,
            joystickModel: joysticks,
            mouseAreaModel: mice,
            bundleIdentifier: keymap.targetHint ?? "",
            version: version
        )
    }

    private static func button(from dto: PlayCoverButtonDTO) -> ButtonElement {
        ButtonElement(
            key: PlayCoverKeyCodeMap.boundKey(fromPlayCover: dto.keyCode, fallbackName: dto.keyName),
            transform: transform(from: dto.transform)
        )
    }

    private static func dto(from button: ButtonElement) -> PlayCoverButtonDTO {
        PlayCoverButtonDTO(
            keyCode: PlayCoverKeyCodeMap.playCoverCode(from: button.key),
            keyName: button.key.name,
            transform: dto(from: button.transform)
        )
    }

    private static func joystick(from dto: PlayCoverJoystickDTO) -> JoystickElement {
        JoystickElement(
            up: PlayCoverKeyCodeMap.boundKey(fromPlayCover: dto.upKeyCode, fallbackName: "W"),
            right: PlayCoverKeyCodeMap.boundKey(fromPlayCover: dto.rightKeyCode, fallbackName: "D"),
            down: PlayCoverKeyCodeMap.boundKey(fromPlayCover: dto.downKeyCode, fallbackName: "S"),
            left: PlayCoverKeyCodeMap.boundKey(fromPlayCover: dto.leftKeyCode, fallbackName: "A"),
            keyName: dto.keyName,
            transform: transform(from: dto.transform),
            floating: dto.mode == 1
        )
    }

    private static func dto(from joystick: JoystickElement) -> PlayCoverJoystickDTO {
        PlayCoverJoystickDTO(
            upKeyCode: PlayCoverKeyCodeMap.playCoverCode(from: joystick.up),
            rightKeyCode: PlayCoverKeyCodeMap.playCoverCode(from: joystick.right),
            downKeyCode: PlayCoverKeyCodeMap.playCoverCode(from: joystick.down),
            leftKeyCode: PlayCoverKeyCodeMap.playCoverCode(from: joystick.left),
            keyName: joystick.keyName,
            transform: dto(from: joystick.transform),
            mode: joystick.floating ? 1 : 0
        )
    }

    private static func mouseArea(from dto: PlayCoverMouseAreaDTO) -> MouseAreaElement {
        MouseAreaElement(
            keyName: dto.keyName,
            transform: transform(from: dto.transform)
        )
    }

    /// PlayCover stores size as percent (`5` = 5%). Canonical size is `0…1`.
    private static func transform(from dto: PlayCoverTransformDTO) -> NormalizedTransform {
        NormalizedTransform(x: dto.xCoord, y: dto.yCoord, size: dto.size)
    }

    private static func dto(from transform: NormalizedTransform) -> PlayCoverTransformDTO {
        PlayCoverTransformDTO(
            size: NormalizedTransform.clampSize(transform.size) * 100,
            xCoord: transform.x,
            yCoord: transform.y
        )
    }
}
