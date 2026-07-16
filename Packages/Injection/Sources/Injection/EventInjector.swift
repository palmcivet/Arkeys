import Foundation
import AppKit
import ApplicationServices
import Targeting

public enum InjectMode: String, Identifiable, Sendable {
    case postToPid
    case skyLight
    case hidTap
    case cascade

    public var id: String { rawValue }

    public static var productCases: [InjectMode] {
        [.cascade, .postToPid, .skyLight, .hidTap]
    }

    public func isAvailable(given report: CapabilityReport) -> Bool {
        switch self {
        case .postToPid:
            return report.accessibilityTrusted
        case .skyLight:
            return report.skyLightPostToPid
        case .hidTap:
            return report.eventTapCreatable
        case .cascade:
            return report.accessibilityTrusted
                || report.skyLightPostToPid
                || report.eventTapCreatable
        }
    }

    /// Resolve a persisted/raw mode into a usable product mode.
    public static func resolvedProductMode(raw: String?, report: CapabilityReport?) -> InjectMode {
        let candidate: InjectMode
        if let raw, let mode = InjectMode(rawValue: raw), productCases.contains(mode) {
            candidate = mode
        } else {
            candidate = .cascade
        }
        guard let report else { return candidate }
        if candidate.isAvailable(given: report) { return candidate }
        return productCases.first { $0.isAvailable(given: report) } ?? .postToPid
    }
}

public struct InjectResult: Sendable {
    public let mode: InjectMode
    public let posted: Bool
    public let detail: String
    public let cursorBefore: CGPoint
    public let cursorAfter: CGPoint
    public let elapsedMs: Int

    public var summary: String {
        let delta = InjectLogger.formatDelta(from: cursorBefore, to: cursorAfter)
        return "mode=\(mode.rawValue) result=\(posted ? "posted" : "failed") detail=\(detail) cursorDelta=\(delta) elapsedMs=\(elapsedMs)"
    }
}

private enum CGMouseEventField {
    static let windowUnderMousePointer: CGEventField = CGEventField(rawValue: 91)!
    static let windowUnderMousePointerThatCanHandleThisEvent: CGEventField = CGEventField(rawValue: 92)!
    /// Chromium/Electron treat subtype 3 as a "real mouse" event.
    /// Without this, the renderer IPC boundary drops synthetic clicks.
    static let chromiumTrustedSubtype: Int64 = 3
}

public final class EventInjector: @unchecked Sendable {
    public var preferMouseMovedBeforeHID: Bool = true
    public var restoreCursorAfterHID: Bool = true

    private let source = CGEventSource(stateID: .hidSystemState)

    public init() {}

    public func injectClick(mode: InjectMode, target: InjectionTarget) -> InjectResult {
        switch mode {
        case .postToPid:
            return runTimed(mode: mode) { _ in
                postToPidClick(target: target)
            }
        case .skyLight:
            return runTimed(mode: mode) { _ in
                skyLightClick(target: target)
            }
        case .hidTap:
            return runTimed(mode: mode) { before in
                hidTapClick(target: target, cursorBefore: before)
            }
        case .cascade:
            return cascadeClick(target: target)
        }
    }

    // MARK: - Per-PID targeted click (postToPid / SkyLight)

    private func postToPidClick(target: InjectionTarget) -> (Bool, String) {
        guard let down = makeTargetedMouseEvent(type: .leftMouseDown, target: target),
              let up = makeTargetedMouseEvent(type: .leftMouseUp, target: target) else {
            return (false, "eventCreateFailed")
        }
        down.postToPid(target.pid)
        up.postToPid(target.pid)
        return (true, "postToPid")
    }

    private func skyLightClick(target: InjectionTarget) -> (Bool, String) {
        guard SkyLightBridge.shared.isAvailable else {
            return (false, "skyLightUnavailable")
        }
        guard let down = makeTargetedMouseEvent(type: .leftMouseDown, target: target),
              let up = makeTargetedMouseEvent(type: .leftMouseUp, target: target) else {
            return (false, "eventCreateFailed")
        }
        let okDown = SkyLightBridge.shared.post(down, to: target.pid)
        let okUp = SkyLightBridge.shared.post(up, to: target.pid)
        return (okDown && okUp, okDown && okUp ? "SLEventPostToPid" : "skyLightPostFailed")
    }

    // MARK: - Global HID click (moves cursor, works for all targets)

    private func hidTapClick(target: InjectionTarget, cursorBefore: CGPoint) -> (Bool, String) {
        let point = target.clickPointQuartz
        var notes: [String] = []

        // Warp cursor synchronously to the click point. This is more reliable
        // than posting a mouseMoved event (which is async and might not be
        // processed before the mouseDown arrives).
        CGWarpMouseCursorPosition(point)
        // Re-associate to suppress the "mouse acceleration catchup" after warp.
        CGAssociateMouseAndMouseCursorPosition(1)
        notes.append("warpTo")

        if preferMouseMovedBeforeHID {
            if let moved = makeHIDMouseEvent(type: .mouseMoved, at: point, windowID: target.windowID) {
                moved.post(tap: .cghidEventTap)
                notes.append("mouseMoved")
            }
            usleep(10_000)
        }

        guard let down = makeHIDMouseEvent(type: .leftMouseDown, at: point, windowID: target.windowID),
              let up = makeHIDMouseEvent(type: .leftMouseUp, at: point, windowID: target.windowID) else {
            return (false, "eventCreateFailed")
        }

        down.post(tap: .cghidEventTap)

        // iOS-on-Mac apps (UIKit compat layer) need a realistic hold duration.
        // CGEvent clicks complete in <1ms; UIScrollView's delaysContentTouches
        // waits ~150ms. A 60ms hold is enough for button taps in most games.
        if target.isIOSOnMac {
            usleep(60_000)
        }

        up.post(tap: .cghidEventTap)
        notes.append("hidDownUp")

        if restoreCursorAfterHID {
            if target.isIOSOnMac {
                usleep(30_000)
            }
            let restoreQuartz = TargetResolver.appKitToQuartz(cursorBefore)
            CGWarpMouseCursorPosition(restoreQuartz)
            CGAssociateMouseAndMouseCursorPosition(1)
            notes.append("warpRestore")
        }
        return (true, notes.joined(separator: "+"))
    }

    // MARK: - Cascade (auto-select best route)

    private func cascadeClick(target: InjectionTarget) -> InjectResult {
        let before = NSEvent.mouseLocation
        let start = CFAbsoluteTimeGetCurrent()
        var steps: [String] = []

        // iOS-on-Mac apps (UIKit touch pipeline) ignore postToPid/SkyLight CGEvents.
        // Only events from the real HID stream reach their touch translation layer.
        if target.isIOSOnMac {
            let hid = hidTapClick(target: target, cursorBefore: before)
            steps.append(cascadeStep("hidTap(iOSOnMac)", hid))
            return finishCascade(steps: steps, posted: hid.0, before: before, start: start)
        }

        let pidResult = postToPidClick(target: target)
        steps.append(cascadeStep("postToPid", pidResult))
        if pidResult.0 {
            return finishCascade(steps: steps, posted: true, before: before, start: start)
        }

        let sky = skyLightClick(target: target)
        steps.append(cascadeStep("skyLight", sky))
        if sky.0 {
            return finishCascade(steps: steps, posted: true, before: before, start: start)
        }

        let hid = hidTapClick(target: target, cursorBefore: before)
        steps.append(cascadeStep("hidTap", hid))
        return finishCascade(steps: steps, posted: hid.0, before: before, start: start)
    }

    private func cascadeStep(_ name: String, _ result: (Bool, String)) -> String {
        if result.0 {
            if result.1 == name || result.1.isEmpty {
                return "\(name)=ok"
            }
            return "\(name)=ok(\(result.1))"
        }
        return "\(name)=fail(\(result.1))"
    }

    private func finishCascade(steps: [String], posted: Bool, before: CGPoint, start: CFAbsoluteTime) -> InjectResult {
        let after = NSEvent.mouseLocation
        let elapsed = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
        let result = InjectResult(
            mode: .cascade,
            posted: posted,
            detail: steps.joined(separator: " | "),
            cursorBefore: before,
            cursorAfter: after,
            elapsedMs: elapsed
        )
        InjectLogger.log(.inject, result.summary)
        return result
    }

    // MARK: - Targeted event construction (postToPid / SkyLight)

    /// Construct a high-fidelity mouse event via `NSEvent` → `.cgEvent` extraction.
    /// Auto-fills ~12 internal fields (source PID, user/group IDs, event-type
    /// mirrors, window number, etc.) that raw `CGEvent` skips, making the
    /// event indistinguishable from a real user click to most apps.
    private func makeTargetedMouseEvent(type: CGEventType, target: InjectionTarget) -> CGEvent? {
        let point = target.clickPointQuartz
        let isClick = type == .leftMouseDown || type == .leftMouseUp

        let nsType: NSEvent.EventType
        switch type {
        case .leftMouseDown: nsType = .leftMouseDown
        case .leftMouseUp:   nsType = .leftMouseUp
        case .mouseMoved:    nsType = .mouseMoved
        default:             nsType = .leftMouseDown
        }

        let nsEvent = NSEvent.mouseEvent(
            with: nsType,
            location: NSPoint(x: point.x, y: point.y),
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: Int(target.windowID ?? 0),
            context: nil,
            eventNumber: Self.nextEventNumber(),
            clickCount: isClick ? 1 : 0,
            pressure: type == .leftMouseDown ? 1.0 : 0.0
        )
        guard let event = nsEvent?.cgEvent else { return nil }

        event.location = point

        if isClick {
            event.setIntegerValueField(.mouseEventClickState, value: 1)
            event.setIntegerValueField(.mouseEventButtonNumber, value: 0)
            event.setIntegerValueField(.mouseEventSubtype, value: CGMouseEventField.chromiumTrustedSubtype)
        }

        if let windowID = target.windowID {
            event.setIntegerValueField(CGMouseEventField.windowUnderMousePointer, value: Int64(windowID))
            event.setIntegerValueField(CGMouseEventField.windowUnderMousePointerThatCanHandleThisEvent, value: Int64(windowID))
        }

        // Window-local coordinates via private CGEventSetWindowLocation.
        let windowLocal = TargetResolver.windowLocalQuartz(point: point, windowFrameAppKit: target.windowFrame)
        _ = SkyLightBridge.shared.setWindowLocation(event, to: windowLocal)

        // When target is backgrounded, set maskCommand (0x00100000) as a
        // WindowServer filter bypass. NOT maskNonCoalesced (0x100).
        let targetIsActive = NSRunningApplication(processIdentifier: target.pid)?.isActive ?? false
        if !targetIsActive {
            event.flags = .maskCommand
        }

        return event
    }

    private static let eventCounter = OSAtomicCounter()
    private static func nextEventNumber() -> Int {
        eventCounter.increment()
    }

    // MARK: - HID event construction (global tap fallback)

    /// Simpler construction for events posted via `.cghidEventTap`.
    /// No maskCommand (would be seen as Cmd held down by WindowServer).
    private func makeHIDMouseEvent(type: CGEventType, at point: CGPoint, windowID: CGWindowID?) -> CGEvent? {
        guard let event = CGEvent(
            mouseEventSource: source,
            mouseType: type,
            mouseCursorPosition: point,
            mouseButton: .left
        ) else {
            return nil
        }
        if type == .leftMouseDown || type == .leftMouseUp {
            event.setIntegerValueField(.mouseEventClickState, value: 1)
            event.setIntegerValueField(.mouseEventButtonNumber, value: 0)
            event.setIntegerValueField(.mouseEventSubtype, value: CGMouseEventField.chromiumTrustedSubtype)
        }
        if let windowID {
            event.setIntegerValueField(CGMouseEventField.windowUnderMousePointer, value: Int64(windowID))
            event.setIntegerValueField(CGMouseEventField.windowUnderMousePointerThatCanHandleThisEvent, value: Int64(windowID))
        }
        return event
    }

    private func runTimed(mode: InjectMode, body: (CGPoint) -> (Bool, String)) -> InjectResult {
        let before = NSEvent.mouseLocation
        let start = CFAbsoluteTimeGetCurrent()
        let (posted, detail) = body(before)
        let after = NSEvent.mouseLocation
        let elapsed = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
        let result = InjectResult(
            mode: mode,
            posted: posted,
            detail: detail,
            cursorBefore: before,
            cursorAfter: after,
            elapsedMs: elapsed
        )
        InjectLogger.log(.inject, result.summary)
        return result
    }
}

// MARK: - Thread-safe event-number counter

private final class OSAtomicCounter: @unchecked Sendable {
    private var _value: Int = 0
    private var _lock = os_unfair_lock()

    func increment() -> Int {
        os_unfair_lock_lock(&_lock)
        _value += 1
        let v = _value
        os_unfair_lock_unlock(&_lock)
        return v
    }
}
