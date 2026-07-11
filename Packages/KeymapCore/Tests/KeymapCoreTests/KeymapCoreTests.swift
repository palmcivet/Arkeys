import XCTest
@testable import KeymapCore

final class KeymapCoreTests: XCTestCase {
    func testButtonLookupByKeyCode() {
        var map = CanonicalKeymap()
        map.elements.append(.button(ButtonElement(
            key: .virtual(40, name: "K"),
            transform: NormalizedTransform(x: 0.5, y: 0.5, size: 0.05)
        )))
        XCTAssertEqual(map.button(matchingKeyCode: 40)?.key.name, "K")
        XCTAssertNil(map.button(matchingKeyCode: 38))
    }

    func testStoreRoundTrip() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = KeymapStore(directory: dir)
        var map = CanonicalKeymap(targetHint: "com.example.app", source: .striker(version: "1"))
        map.elements = [
            .button(ButtonElement(key: .virtual(0, name: "A"), transform: .init(x: 0.1, y: 0.2, size: 0.05)))
        ]
        try store.save(map, bundleID: "com.example.app")
        let loaded = store.load(bundleID: "com.example.app")
        XCTAssertEqual(loaded?.runnableButtons.first?.key.name, "A")
    }
}
