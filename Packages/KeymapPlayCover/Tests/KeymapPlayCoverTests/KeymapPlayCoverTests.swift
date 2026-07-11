import XCTest
import KeymapCore
@testable import KeymapPlayCover

final class KeymapPlayCoverTests: XCTestCase {
    func testDecodeFixture() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "sample", withExtension: "playmap", subdirectory: "Fixtures")
            ?? Bundle.module.url(forResource: "sample", withExtension: "playmap"))
        let data = try Data(contentsOf: url)
        let parser = PlayCoverKeymapParser()
        let map = try parser.decode(data)

        XCTAssertEqual(map.targetHint, "com.example.demo")
        XCTAssertEqual(map.runnableButtons.count, 2)
        XCTAssertEqual(map.elements.count, 3) // 2 buttons + 1 joystick

        let k = try XCTUnwrap(map.button(matchingKeyCode: 40)) // K = NSEvent 40
        XCTAssertEqual(k.key.name, "K")
        XCTAssertEqual(k.transform.x, 0.25, accuracy: 0.0001)

        if case .playCover(let version) = map.source {
            XCTAssertEqual(version, "2.0.0")
        } else {
            XCTFail("expected playCover source")
        }
    }

    func testRoundTripButtons() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "sample", withExtension: "playmap", subdirectory: "Fixtures")
            ?? Bundle.module.url(forResource: "sample", withExtension: "playmap"))
        let data = try Data(contentsOf: url)
        let parser = PlayCoverKeymapParser()
        let map = try parser.decode(data)
        let encoded = try parser.encode(map)
        let again = try parser.decode(encoded)
        XCTAssertEqual(again.runnableButtons.count, map.runnableButtons.count)
        XCTAssertEqual(again.button(matchingKeyCode: 40)?.transform.x, 0.25)
    }

    func testRegistryDetect() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "sample", withExtension: "playmap", subdirectory: "Fixtures")
            ?? Bundle.module.url(forResource: "sample", withExtension: "playmap"))
        let data = try Data(contentsOf: url)
        let registry = KeymapSchemeRegistry(parserTypes: [PlayCoverKeymapParser.self])
        let map = try registry.importKeymap(data: data, filename: "sample.playmap")
        XCTAssertEqual(map.targetHint, "com.example.demo")
    }

    func testGCKeyMapping() {
        // GC 14 = K → NSEvent 40
        XCTAssertEqual(PlayCoverKeyCodeMap.nsEventKeyCode(fromGC: 14), 40)
        XCTAssertEqual(PlayCoverKeyCodeMap.gcCode(fromNSEvent: 40), 14)
    }
}
