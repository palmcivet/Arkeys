import Foundation
import KeymapCore

/// Bidirectional map between PlayCover/GameController-style codes and NSEvent virtual key codes.
enum PlayCoverKeyCodeMap {
    /// GC/PlayCover Int → NSEvent keyCode (or special KeyCode).
    static func boundKey(fromPlayCover code: Int, fallbackName: String) -> BoundKey {
        if let special = specialBoundKey(code: code, name: fallbackName) {
            return special
        }
        if let ns = nsEventKeyCode(fromGC: code) {
            let name = fallbackName.isEmpty ? CarbonKeyNames.name(for: ns) : fallbackName
            return .virtual(ns, name: name)
        }
        let name = fallbackName.isEmpty ? "Key\(code)" : fallbackName
        return BoundKey(code: .unknown(code), name: name)
    }

    static func playCoverCode(from key: BoundKey) -> Int {
        switch key.code {
        case .leftMouse: return -1
        case .rightMouse: return -2
        case .middleMouse: return -3
        case .unknown(let raw): return raw
        case .virtual(let ns):
            return gcCode(fromNSEvent: ns) ?? Int(ns)
        }
    }

    private static func specialBoundKey(code: Int, name: String) -> BoundKey? {
        switch code {
        case -1: return BoundKey(code: .leftMouse, name: name.isEmpty ? "LMB" : name)
        case -2: return BoundKey(code: .rightMouse, name: name.isEmpty ? "RMB" : name)
        case -3: return BoundKey(code: .middleMouse, name: name.isEmpty ? "MMB" : name)
        default: return nil
        }
    }

    /// Subset of PlayTools `mapNSEventVirtualCodeToGCKeyCodeRawValue` inverted for letters/digits/common keys.
    private static let nsToGC: [UInt16: Int] = [
        0: 4, 1: 22, 2: 7, 3: 9, 4: 11, 5: 10, 6: 29, 7: 27,
        8: 6, 9: 25, 11: 5, 12: 20, 13: 26, 14: 8, 15: 21,
        16: 28, 17: 23, 18: 30, 19: 31, 20: 32, 21: 33, 22: 35,
        23: 34, 24: 46, 25: 38, 26: 36, 27: 45, 28: 37, 29: 39,
        30: 48, 31: 18, 32: 24, 33: 47, 34: 12, 35: 19, 36: 40,
        37: 15, 38: 13, 39: 52, 40: 14, 41: 51, 42: 49, 43: 54,
        44: 56, 45: 17, 46: 16, 47: 55, 48: 43, 49: 44, 50: 53,
        51: 42, 53: 41,
        123: 80, 124: 79, 125: 81, 126: 82,
        122: 58, 120: 59, 99: 60, 118: 61, 96: 62, 97: 63,
        98: 64, 100: 65, 101: 66, 109: 67, 103: 68, 111: 69,
    ]

    private static let gcToNS: [Int: UInt16] = {
        Dictionary(uniqueKeysWithValues: nsToGC.map { ($0.value, $0.key) })
    }()

    static func nsEventKeyCode(fromGC code: Int) -> UInt16? {
        gcToNS[code]
    }

    static func gcCode(fromNSEvent code: UInt16) -> Int? {
        nsToGC[code]
    }
}
