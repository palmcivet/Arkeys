import XCTest
import KeymapCore
@testable import EditorKit

final class EditorHandleLayoutTests: XCTestCase {
    func testCornerResizeKeepsHandleUnderCursor() {
        let unscaled = 22.0
        let minScale = 1.0
        let maxScale = 144.0 / 22.0

        let atRest = EditorHandleLayout.sizeAfterCornerResize(
            cursorX: 11,
            cursorY: 11,
            centerX: 0,
            centerY: 0,
            unscaledWidth: unscaled,
            unscaledHeight: unscaled,
            minScale: minScale,
            maxScale: maxScale
        )
        XCTAssertEqual(atRest, NormalizedTransform.defaultSize, accuracy: 0.0001)

        let doubled = EditorHandleLayout.sizeAfterCornerResize(
            cursorX: 22,
            cursorY: 22,
            centerX: 0,
            centerY: 0,
            unscaledWidth: unscaled,
            unscaledHeight: unscaled,
            minScale: minScale,
            maxScale: maxScale
        )
        XCTAssertEqual(doubled, NormalizedTransform.defaultSize * 2, accuracy: 0.0001)

        let wide = EditorHandleLayout.sizeAfterCornerResize(
            cursorX: 40,
            cursorY: 22,
            centerX: 0,
            centerY: 0,
            unscaledWidth: 40,
            unscaledHeight: 22,
            minScale: minScale,
            maxScale: maxScale
        )
        XCTAssertEqual(wide, NormalizedTransform.defaultSize * 2, accuracy: 0.0001)

        let atMax = EditorHandleLayout.sizeAfterCornerResize(
            cursorX: 400,
            cursorY: 400,
            centerX: 0,
            centerY: 0,
            unscaledWidth: unscaled,
            unscaledHeight: unscaled,
            minScale: minScale,
            maxScale: maxScale
        )
        XCTAssertEqual(atMax, NormalizedTransform.clampSize(NormalizedTransform.defaultSize * maxScale), accuracy: 0.0001)

        let atMin = EditorHandleLayout.sizeAfterCornerResize(
            cursorX: 0,
            cursorY: 0,
            centerX: 0,
            centerY: 0,
            unscaledWidth: unscaled,
            unscaledHeight: unscaled,
            minScale: minScale,
            maxScale: maxScale
        )
        XCTAssertEqual(atMin, NormalizedTransform.defaultSize, accuracy: 0.0001)
    }
}
