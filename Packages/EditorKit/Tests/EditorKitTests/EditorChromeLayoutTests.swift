import XCTest
import KeymapCore
@testable import EditorKit

final class EditorChromeLayoutTests: XCTestCase {
    private let canvas = CGSize(width: 800, height: 600)
    private let bar = CGSize(width: 400, height: 36)

    func testBarSitsBottomCenterByDefault() {
        let frame = EditorChromeDodge.barFrame(edge: .bottom, canvas: canvas, barSize: bar)
        XCTAssertEqual(frame.minX, 200, accuracy: 0.5)
        XCTAssertEqual(frame.maxY, canvas.height - EditorChromeDodge.margin, accuracy: 0.5)
        XCTAssertEqual(frame.height, bar.height)
    }

    func testBarSitsTopCenterWhenFlipped() {
        let frame = EditorChromeDodge.barFrame(edge: .top, canvas: canvas, barSize: bar)
        XCTAssertEqual(frame.minX, 200, accuracy: 0.5)
        XCTAssertEqual(frame.minY, EditorChromeDodge.margin, accuracy: 0.5)
    }

    func testStaysPutWhenNothingIsNearby() {
        XCTAssertEqual(
            EditorChromeDodge.resolve(current: .top, canvas: canvas, barSize: bar, obstacles: []),
            .top
        )
        XCTAssertEqual(
            EditorChromeDodge.resolve(current: .bottom, canvas: canvas, barSize: bar, obstacles: []),
            .bottom
        )
    }

    func testFlipsToTopWhenKeycapEntersBottomApproach() {
        let key = CGRect(x: 360, y: 540, width: 80, height: 40)
        let edge = EditorChromeDodge.resolve(
            current: .bottom,
            canvas: canvas,
            barSize: bar,
            obstacles: [key]
        )
        XCTAssertEqual(edge, .top)
    }

    func testStaysTopWhileKeycapStillCoversBottom() {
        let key = CGRect(x: 360, y: 540, width: 80, height: 40)
        let edge = EditorChromeDodge.resolve(
            current: .top,
            canvas: canvas,
            barSize: bar,
            obstacles: [key]
        )
        XCTAssertEqual(edge, .top)
    }

    func testDoesNotReturnAfterKeycapLeaves() {
        let key = CGRect(x: 360, y: 200, width: 80, height: 40)
        let edge = EditorChromeDodge.resolve(
            current: .top,
            canvas: canvas,
            barSize: bar,
            obstacles: [key]
        )
        XCTAssertEqual(edge, .top)
    }

    func testReturnsOnlyWhenKeycapEntersTheOtherSide() {
        let topKey = CGRect(x: 360, y: 8, width: 80, height: 40)
        let edge = EditorChromeDodge.resolve(
            current: .top,
            canvas: canvas,
            barSize: bar,
            obstacles: [topKey]
        )
        XCTAssertEqual(edge, .bottom)
    }

    func testFlipsEvenWhenOtherSideHasAKeycap() {
        let bottomKey = CGRect(x: 360, y: 540, width: 80, height: 40)
        let topKey = CGRect(x: 360, y: 8, width: 80, height: 40)
        XCTAssertEqual(
            EditorChromeDodge.resolve(
                current: .bottom,
                canvas: canvas,
                barSize: bar,
                obstacles: [bottomKey, topKey]
            ),
            .top
        )
        XCTAssertEqual(
            EditorChromeDodge.resolve(
                current: .top,
                canvas: canvas,
                barSize: bar,
                obstacles: [bottomKey, topKey]
            ),
            .bottom
        )
    }

    func testFittedBarWidthUsesMinWhenContentFits() {
        XCTAssertEqual(
            EditorChromeDodge.fittedBarWidth(canvasWidth: 1400, contentWidth: 280),
            EditorChromeDodge.barMinWidth,
            accuracy: 0.5
        )
        XCTAssertEqual(
            EditorChromeDodge.fittedBarWidth(canvasWidth: 1400),
            EditorChromeDodge.barMinWidth,
            accuracy: 0.5
        )
    }

    func testFittedBarWidthGrowsWithContent() {
        XCTAssertEqual(
            EditorChromeDodge.fittedBarWidth(canvasWidth: 1400, contentWidth: 520),
            520,
            accuracy: 0.5
        )
    }

    func testFittedBarWidthCapsAtMax() {
        XCTAssertEqual(
            EditorChromeDodge.fittedBarWidth(canvasWidth: 1400, contentWidth: 800),
            EditorChromeDodge.barMaxWidth,
            accuracy: 0.5
        )
    }

    func testFittedBarWidthCapsAtCanvas() {
        let canvasWidth: CGFloat = 500
        let expected = canvasWidth - EditorChromeDodge.horizontalInset * 2
        XCTAssertEqual(
            EditorChromeDodge.fittedBarWidth(canvasWidth: canvasWidth, contentWidth: 800),
            expected,
            accuracy: 0.5
        )
        XCTAssertLessThan(expected, EditorChromeDodge.barMaxWidth)
        XCTAssertGreaterThan(expected, EditorChromeDodge.barMinWidth)
    }

    func testFittedBarWidthUsesCanvasWhenNarrowerThanMin() {
        let narrow = EditorChromeDodge.fittedBarWidth(canvasWidth: 400)
        XCTAssertEqual(narrow, 400 - EditorChromeDodge.horizontalInset * 2, accuracy: 0.5)
        XCTAssertLessThan(narrow, EditorChromeDodge.barMinWidth)
    }

    func testKeycapFrameIsCenteredOnNormalizedPoint() {
        let frame = EditorChromeDodge.keycapFrame(
            centerX: 400,
            centerY: 300,
            title: "A",
            shape: .circle,
            scale: 1
        )
        XCTAssertEqual(frame.midX, 400, accuracy: 0.5)
        XCTAssertEqual(frame.midY, 300, accuracy: 0.5)
        XCTAssertGreaterThan(frame.width, 0)
    }

    func testBoundStatusSubstitutesName() {
        XCTAssertEqual(
            EditorChromeCopy.english.boundStatus(name: "W"),
            "Bound W — press a key · drag · × to delete"
        )
    }

    func testSelectedStatusSubstitutesName() {
        XCTAssertEqual(
            EditorChromeCopy.english.selectedStatus(name: "Shift"),
            "Selected Shift — press a key · drag · × to delete"
        )
    }

    func testHysteresisDoesNotFlipForDistantKeycap() {
        let far = CGRect(x: 360, y: 400, width: 80, height: 40)
        let edge = EditorChromeDodge.resolve(
            current: .bottom,
            canvas: canvas,
            barSize: bar,
            obstacles: [far]
        )
        XCTAssertEqual(edge, .bottom)
    }
}
