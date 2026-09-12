import XCTest
@testable import KeymapCore

@MainActor
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

    func testUnresolvedButtonCount() {
        var map = CanonicalKeymap()
        map.elements = [
            .button(ButtonElement(
                key: .virtual(0, name: "A"),
                transform: NormalizedTransform(x: 0.1, y: 0.2, size: 0.05)
            )),
            .button(ButtonElement(
                key: BoundKey(code: .unknown(-1), name: "?"),
                transform: NormalizedTransform(x: 0.3, y: 0.2, size: 0.05)
            )),
            .button(ButtonElement(
                key: BoundKey(code: .unknown(999), name: "Key999"),
                transform: NormalizedTransform(x: 0.5, y: 0.2, size: 0.05)
            )),
        ]
        XCTAssertEqual(map.runnableButtons.count, 3)
        XCTAssertEqual(map.unresolvedButtonCount, 2)
        XCTAssertFalse(BoundKey.virtual(0, name: "A").isUnresolved)
        XCTAssertTrue(BoundKey(code: .unknown(-1), name: "?").isUnresolved)
    }

    func testStoreRoundTrip() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = KeymapStore(directory: dir)
        var map = CanonicalKeymap(targetHint: "com.example.app", source: .arkeys(version: "1"))
        map.elements = [
            .button(ButtonElement(key: .virtual(0, name: "A"), transform: .init(x: 0.1, y: 0.2, size: 0.05)))
        ]
        let meta = try store.create(keymap: map, bundleID: "com.example.app", name: "测试方案")
        let loaded = store.load(bundleID: "com.example.app", schemeID: meta.id)
        XCTAssertEqual(loaded?.runnableButtons.first?.key.name, "A")
        XCTAssertEqual(store.loadActive(bundleID: "com.example.app")?.meta.name, "测试方案")
    }

    func testMultiSchemeCreateSelectDelete() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = KeymapStore(directory: dir)
        let bundleID = "com.example.game"

        var mapA = CanonicalKeymap(targetHint: bundleID, source: .arkeys(version: "1"))
        mapA.elements = [
            .button(ButtonElement(key: .virtual(0, name: "A"), transform: .init(x: 0.1, y: 0.2, size: 0.05)))
        ]
        let metaA = try store.create(keymap: mapA, bundleID: bundleID, name: "方案 A")

        var mapB = CanonicalKeymap(targetHint: bundleID, source: .playCover(version: "2"))
        mapB.elements = [
            .button(ButtonElement(key: .virtual(1, name: "S"), transform: .init(x: 0.3, y: 0.4, size: 0.05)))
        ]
        let metaB = try store.create(keymap: mapB, bundleID: bundleID, name: "方案 B")

        let listed = store.listSchemes(bundleID: bundleID)
        XCTAssertEqual(listed.count, 2)
        XCTAssertEqual(store.activeSchemeID(bundleID: bundleID), metaB.id)
        XCTAssertEqual(store.loadActive(bundleID: bundleID)?.keymap.runnableButtons.first?.key.name, "S")

        try store.setActive(schemeID: metaA.id, bundleID: bundleID)
        XCTAssertEqual(store.activeSchemeID(bundleID: bundleID), metaA.id)
        XCTAssertEqual(store.load(bundleID: bundleID, schemeID: metaA.id)?.runnableButtons.first?.key.name, "A")

        try store.rename(schemeID: metaA.id, bundleID: bundleID, name: "主方案")
        XCTAssertEqual(store.listSchemes(bundleID: bundleID).first { $0.id == metaA.id }?.name, "主方案")

        try store.delete(schemeID: metaA.id, bundleID: bundleID)
        XCTAssertEqual(store.listSchemes(bundleID: bundleID).count, 1)
        XCTAssertEqual(store.activeSchemeID(bundleID: bundleID), metaB.id)
    }

    func testListAllTargetsAndCopyScheme() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = KeymapStore(directory: dir)

        var map = CanonicalKeymap(targetHint: "com.game.kr", source: .arkeys(version: "1"))
        map.elements = [
            .button(ButtonElement(key: .virtual(0, name: "A"), transform: .init(x: 0.1, y: 0.2, size: 0.05)))
        ]
        let source = try store.create(keymap: map, bundleID: "com.game.kr", name: "主方案")
        store.setDisplayName("Arknights KR", bundleID: "com.game.kr")

        XCTAssertEqual(store.listAllTargets().count, 1)
        XCTAssertEqual(store.listAllTargets().first?.bundleID, "com.game.kr")
        XCTAssertEqual(store.listAllTargets().first?.manifest.displayName, "Arknights KR")

        let copied = try store.copyScheme(
            fromBundleID: "com.game.kr",
            schemeID: source.id,
            toBundleID: "com.game.en",
            name: nil
        )
        XCTAssertNotEqual(copied.id, source.id)
        XCTAssertEqual(copied.name, "主方案")
        XCTAssertEqual(store.load(bundleID: "com.game.en", schemeID: copied.id)?.runnableButtons.first?.key.name, "A")
        XCTAssertEqual(store.activeSchemeID(bundleID: "com.game.en"), copied.id)
        XCTAssertEqual(store.activeSchemeID(bundleID: "com.game.kr"), source.id)

        let targets = store.listAllTargets()
        XCTAssertEqual(targets.map(\.bundleID), ["com.game.en", "com.game.kr"])
    }

    func testCopySchemeDoesNotStealExistingActive() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = KeymapStore(directory: dir)

        let dest = try store.create(
            keymap: CanonicalKeymap(targetHint: "com.game.en", source: .arkeys(version: "1")),
            bundleID: "com.game.en",
            name: "English"
        )
        let source = try store.create(
            keymap: CanonicalKeymap(targetHint: "com.game.kr", source: .arkeys(version: "1")),
            bundleID: "com.game.kr",
            name: "Korean"
        )

        let copied = try store.copyScheme(
            fromBundleID: "com.game.kr",
            schemeID: source.id,
            toBundleID: "com.game.en",
            name: source.name
        )
        XCTAssertEqual(store.activeSchemeID(bundleID: "com.game.en"), dest.id)
        XCTAssertNotEqual(copied.id, dest.id)
        XCTAssertEqual(store.listSchemes(bundleID: "com.game.en").count, 2)
    }

    func testSaveWithoutNameUsesUntitledFallback() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = KeymapStore(directory: dir)
        let schemeID = UUID()

        try store.save(
            CanonicalKeymap(targetHint: "com.example.app", source: .arkeys(version: "1")),
            bundleID: "com.example.app",
            schemeID: schemeID
        )
        XCTAssertEqual(store.listSchemes(bundleID: "com.example.app").first?.name, KeymapSchemeMeta.untitledName)
    }

    func testListAllTargetsSkipsLooseFiles() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = KeymapStore(directory: dir)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("not a target".utf8).write(to: dir.appendingPathComponent("readme.txt"))

        _ = try store.create(
            keymap: CanonicalKeymap(targetHint: "com.example.app", source: .arkeys(version: "1")),
            bundleID: "com.example.app",
            name: "Main"
        )
        XCTAssertEqual(store.listAllTargets().map(\.bundleID), ["com.example.app"])
    }

    func testDeleteTargetRemovesLibrary() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = KeymapStore(directory: dir)
        let bundleID = "com.example.gone"

        _ = try store.create(
            keymap: CanonicalKeymap(targetHint: bundleID, source: .arkeys(version: "1")),
            bundleID: bundleID,
            name: "主方案"
        )
        XCTAssertEqual(store.listAllTargets().count, 1)

        try store.deleteTarget(bundleID: bundleID)
        XCTAssertTrue(store.listAllTargets().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.targetDirectory(forBundleID: bundleID).path))
        XCTAssertTrue(store.listSchemes(bundleID: bundleID).isEmpty)
    }

    func testDeleteLastSchemeRemovesTargetDirectory() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = KeymapStore(directory: dir)
        let bundleID = "com.example.last"

        let meta = try store.create(
            keymap: CanonicalKeymap(targetHint: bundleID, source: .arkeys(version: "1")),
            bundleID: bundleID,
            name: "唯一方案"
        )
        try store.delete(schemeID: meta.id, bundleID: bundleID)

        XCTAssertTrue(store.listSchemes(bundleID: bundleID).isEmpty)
        XCTAssertTrue(store.listAllTargets().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.targetDirectory(forBundleID: bundleID).path))
    }

    func testAppSettingsRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("settings.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let store = AppSettingsStore(fileURL: url)
        let settings = AppSettings(
            lastTargetBundleID: "com.example.app",
            lastTargetAppName: "Example",
            isEnabled: false,
            injectModeRaw: "hidTap",
            preferMouseMovedBeforeHID: false,
            restoreCursorAfterHID: true,
            showMenuBarIcon: false,
            keymapButtonShape: .rectangle,
            showKeymapOverlay: true
        )
        try store.save(settings)
        let loaded = store.load()
        XCTAssertEqual(loaded.lastTargetBundleID, "com.example.app")
        XCTAssertEqual(loaded.injectModeRaw, "hidTap")
        XCTAssertFalse(loaded.isEnabled)
        XCTAssertFalse(loaded.preferMouseMovedBeforeHID)
        XCTAssertFalse(loaded.showMenuBarIcon)
        XCTAssertEqual(loaded.keymapButtonShape, .rectangle)
        XCTAssertTrue(loaded.showKeymapOverlay)
    }

    func testAppSettingsDefaultsMissingOptionalFields() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("settings.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let legacy = """
        {"isEnabled":true,"injectModeRaw":"cascade","showMenuBarIcon":true}
        """
        try Data(legacy.utf8).write(to: url)
        let loaded = AppSettingsStore(fileURL: url).load()
        XCTAssertEqual(loaded.keymapButtonShape, .circle)
        XCTAssertFalse(loaded.showKeymapOverlay)
    }

    func testNormalizedSizeClampAndPlayCoverPercent() throws {
        XCTAssertEqual(NormalizedTransform.clampSize(0.06), 0.06)
        XCTAssertEqual(NormalizedTransform.clampSize(0.01), NormalizedTransform.minSize)
        XCTAssertEqual(NormalizedTransform.clampSize(0.9), NormalizedTransform.maxSize)
        XCTAssertEqual(NormalizedTransform.clampSize(5), 0.05)
        XCTAssertEqual(NormalizedTransform.normalizedSize(8), 0.08)
        XCTAssertEqual(NormalizedTransform(x: 0, y: 0, size: 5).size, 0.05)

        let data = Data(#"{"x":0.1,"y":0.2,"size":5}"#.utf8)
        let loaded = try JSONDecoder().decode(NormalizedTransform.self, from: data)
        XCTAssertEqual(loaded.size, 0.05)
    }

    func testVisualScaleUsesDefaultAsIdentity() {
        XCTAssertEqual(NormalizedTransform.visualScale(size: 0.06, minScale: 1, maxScale: 6), 1, accuracy: 0.0001)
        XCTAssertEqual(NormalizedTransform.visualScale(size: 0.12, minScale: 1, maxScale: 6), 2, accuracy: 0.0001)
        XCTAssertEqual(NormalizedTransform.visualScale(size: 0.01, minScale: 1, maxScale: 6), 1, accuracy: 0.0001)
        XCTAssertEqual(NormalizedTransform.visualScale(size: 0.9, minScale: 1, maxScale: 6), 6, accuracy: 0.0001)
    }
}
