import XCTest
import KeymapCore
@testable import EditorKit

@MainActor
final class EditorGeometryActionTests: XCTestCase {
    func testNudgeMovesAndClamps() {
        let controller = KeymapEditorController()
        let button = ButtonElement(
            key: .virtual(13, name: "W"),
            transform: NormalizedTransform(x: 0.5, y: 0.5, size: NormalizedTransform.defaultSize)
        )
        controller.keymap.elements = [.button(button)]

        controller.nudge(id: button.id, dx: 1, dy: 0)
        XCTAssertEqual(controller.buttonTransform(id: button.id)?.x ?? 0, 0.52, accuracy: 0.0001)

        controller.nudge(id: button.id, dx: 0, dy: -100)
        XCTAssertEqual(controller.buttonTransform(id: button.id)?.y ?? 1, 0, accuracy: 0.0001)
    }

    func testAdjustSizeGrowsAndClamps() {
        let controller = KeymapEditorController()
        let button = ButtonElement(
            key: .virtual(13, name: "W"),
            transform: NormalizedTransform(x: 0.5, y: 0.5, size: NormalizedTransform.defaultSize)
        )
        controller.keymap.elements = [.button(button)]

        controller.adjustSize(id: button.id, factor: KeymapEditorController.sizeFactor)
        let grown = controller.buttonTransform(id: button.id)?.size ?? 0
        XCTAssertEqual(grown, NormalizedTransform.defaultSize * KeymapEditorController.sizeFactor, accuracy: 0.0001)

        controller.adjustSize(id: button.id, factor: 1 / KeymapEditorController.sizeFactor)
        XCTAssertEqual(
            controller.buttonTransform(id: button.id)?.size ?? 0,
            NormalizedTransform.defaultSize,
            accuracy: 0.0001
        )

        let nearMax = ButtonElement(
            id: button.id,
            key: button.key,
            transform: NormalizedTransform(x: 0.5, y: 0.5, size: 0.38)
        )
        controller.keymap.upsertButton(nearMax)
        controller.adjustSize(id: button.id, factor: KeymapEditorController.sizeFactor)
        XCTAssertEqual(controller.buttonTransform(id: button.id)?.size ?? 0, NormalizedTransform.maxSize, accuracy: 0.0001)
    }
}

private extension KeymapEditorController {
    func buttonTransform(id: UUID) -> NormalizedTransform? {
        keymap.elements.first { $0.id == id }?.buttonElement?.transform
    }
}
