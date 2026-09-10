import XCTest
@testable import EditorKit

final class EditorOverlayPolicyTests: XCTestCase {
    func testShowsWhenTargetIsFrontmost() {
        let decision = EditorOverlayPolicy.decide(
            targetIsFrontmost: true,
            hostIsFrontmost: false,
            hideForHostUI: true,
            statusMenuTracking: false,
            overlayInteraction: false
        )
        XCTAssertEqual(decision, .show)
    }

    func testHidesWhenAnotherAppIsFrontmost() {
        let decision = EditorOverlayPolicy.decide(
            targetIsFrontmost: false,
            hostIsFrontmost: false,
            hideForHostUI: false,
            statusMenuTracking: false,
            overlayInteraction: false
        )
        XCTAssertEqual(decision, .hide)
    }

    func testHidesWhenHostUIIsVisibleEvenIfMouseIsOverTarget() {
        let decision = EditorOverlayPolicy.decide(
            targetIsFrontmost: false,
            hostIsFrontmost: true,
            hideForHostUI: true,
            statusMenuTracking: false,
            overlayInteraction: false
        )
        XCTAssertEqual(decision, .hide)
    }

    func testKeepsOverlayWhileStatusMenuIsOpen() {
        let decision = EditorOverlayPolicy.decide(
            targetIsFrontmost: false,
            hostIsFrontmost: true,
            hideForHostUI: false,
            statusMenuTracking: true,
            overlayInteraction: false
        )
        XCTAssertEqual(decision, .show)
    }

    func testOverlayClickReturnsFocusWhenHostHasNoSettings() {
        let decision = EditorOverlayPolicy.decide(
            targetIsFrontmost: false,
            hostIsFrontmost: true,
            hideForHostUI: false,
            statusMenuTracking: false,
            overlayInteraction: true
        )
        XCTAssertEqual(decision, .showAndReturnFocus)
    }

    func testHostUIWinsOverOverlayClick() {
        let decision = EditorOverlayPolicy.decide(
            targetIsFrontmost: false,
            hostIsFrontmost: true,
            hideForHostUI: true,
            statusMenuTracking: false,
            overlayInteraction: true
        )
        XCTAssertEqual(decision, .hide)
    }

    func testHidesWhenHostIsFrontmostWithNoReasonToShow() {
        let decision = EditorOverlayPolicy.decide(
            targetIsFrontmost: false,
            hostIsFrontmost: true,
            hideForHostUI: false,
            statusMenuTracking: false,
            overlayInteraction: false
        )
        XCTAssertEqual(decision, .hide)
    }
}
