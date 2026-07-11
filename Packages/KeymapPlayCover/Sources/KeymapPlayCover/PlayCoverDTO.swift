import Foundation
import KeymapCore

/// Wire format matching PlayCover/PlayTools Keymap plist.
struct PlayCoverKeymapDTO: Codable {
    var buttonModels: [PlayCoverButtonDTO]
    var draggableButtonModels: [PlayCoverButtonDTO]
    var joystickModel: [PlayCoverJoystickDTO]
    var mouseAreaModel: [PlayCoverMouseAreaDTO]
    var bundleIdentifier: String
    var version: String

    enum CodingKeys: String, CodingKey {
        case buttonModels
        case draggableButtonModels
        case joystickModel
        case mouseAreaModel
        case bundleIdentifier
        case version
    }

    init(
        buttonModels: [PlayCoverButtonDTO] = [],
        draggableButtonModels: [PlayCoverButtonDTO] = [],
        joystickModel: [PlayCoverJoystickDTO] = [],
        mouseAreaModel: [PlayCoverMouseAreaDTO] = [],
        bundleIdentifier: String,
        version: String = "2.0.0"
    ) {
        self.buttonModels = buttonModels
        self.draggableButtonModels = draggableButtonModels
        self.joystickModel = joystickModel
        self.mouseAreaModel = mouseAreaModel
        self.bundleIdentifier = bundleIdentifier
        self.version = version
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        buttonModels = try c.decodeIfPresent([PlayCoverButtonDTO].self, forKey: .buttonModels) ?? []
        draggableButtonModels = try c.decodeIfPresent([PlayCoverButtonDTO].self, forKey: .draggableButtonModels) ?? []
        joystickModel = try c.decodeIfPresent([PlayCoverJoystickDTO].self, forKey: .joystickModel) ?? []
        mouseAreaModel = try c.decodeIfPresent([PlayCoverMouseAreaDTO].self, forKey: .mouseAreaModel) ?? []
        bundleIdentifier = try c.decodeIfPresent(String.self, forKey: .bundleIdentifier) ?? ""
        version = try c.decodeIfPresent(String.self, forKey: .version) ?? "2.0.0"
    }
}

struct PlayCoverTransformDTO: Codable {
    var size: Double
    var xCoord: Double
    var yCoord: Double
}

struct PlayCoverButtonDTO: Codable {
    var keyCode: Int
    var keyName: String
    var transform: PlayCoverTransformDTO

    init(keyCode: Int, keyName: String, transform: PlayCoverTransformDTO) {
        self.keyCode = keyCode
        self.keyName = keyName
        self.transform = transform
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        keyCode = try c.decode(Int.self, forKey: .keyCode)
        keyName = try c.decodeIfPresent(String.self, forKey: .keyName) ?? ""
        transform = try c.decode(PlayCoverTransformDTO.self, forKey: .transform)
    }
}

struct PlayCoverJoystickDTO: Codable {
    var upKeyCode: Int
    var rightKeyCode: Int
    var downKeyCode: Int
    var leftKeyCode: Int
    var keyName: String
    var transform: PlayCoverTransformDTO
    var mode: Int?

    init(
        upKeyCode: Int,
        rightKeyCode: Int,
        downKeyCode: Int,
        leftKeyCode: Int,
        keyName: String,
        transform: PlayCoverTransformDTO,
        mode: Int? = nil
    ) {
        self.upKeyCode = upKeyCode
        self.rightKeyCode = rightKeyCode
        self.downKeyCode = downKeyCode
        self.leftKeyCode = leftKeyCode
        self.keyName = keyName
        self.transform = transform
        self.mode = mode
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        upKeyCode = try c.decode(Int.self, forKey: .upKeyCode)
        rightKeyCode = try c.decode(Int.self, forKey: .rightKeyCode)
        downKeyCode = try c.decode(Int.self, forKey: .downKeyCode)
        leftKeyCode = try c.decode(Int.self, forKey: .leftKeyCode)
        keyName = try c.decodeIfPresent(String.self, forKey: .keyName) ?? "Keyboard"
        transform = try c.decode(PlayCoverTransformDTO.self, forKey: .transform)
        mode = try c.decodeIfPresent(Int.self, forKey: .mode)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(upKeyCode, forKey: .upKeyCode)
        try c.encode(rightKeyCode, forKey: .rightKeyCode)
        try c.encode(downKeyCode, forKey: .downKeyCode)
        try c.encode(leftKeyCode, forKey: .leftKeyCode)
        try c.encode(keyName, forKey: .keyName)
        try c.encode(transform, forKey: .transform)
        try c.encodeIfPresent(mode, forKey: .mode)
    }

    enum CodingKeys: String, CodingKey {
        case upKeyCode, rightKeyCode, downKeyCode, leftKeyCode, keyName, transform, mode
    }
}

struct PlayCoverMouseAreaDTO: Codable {
    var keyName: String
    var transform: PlayCoverTransformDTO

    init(keyName: String, transform: PlayCoverTransformDTO) {
        self.keyName = keyName
        self.transform = transform
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        keyName = try c.decodeIfPresent(String.self, forKey: .keyName) ?? "Mouse"
        transform = try c.decode(PlayCoverTransformDTO.self, forKey: .transform)
    }
}
