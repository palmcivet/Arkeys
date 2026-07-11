import Foundation
import AppKit
import ApplicationServices
import Targeting

public enum InjectMode: String, CaseIterable, Identifiable, Sendable {
    case sessionTap
    case postToPid
    case skyLight
    case hidTap
    case axProbe
    case keyEscape
    case cascade

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .sessionTap: return "sessionTap (baseline)"
        case .postToPid: return "postToPid"
        case .skyLight: return "skyLight"
        case .hidTap: return "hidTap"
        case .axProbe: return "axProbe"
        case .keyEscape: return "keyEscape"
        case .cascade: return "cascade"
        }
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
}

public final class EventInjector: @unchecked Sendable {
    public var preferMouseMovedBeforeHID: Bool = true
    public var restoreCursorAfterHID: Bool = true

    private let source = CGEventSource(stateID: .hidSystemState)

    public init() {}

    public func injectClick(mode: InjectMode, target: InjectionTarget) -> InjectResult {
        switch mode {
        case .sessionTap:
            return runTimed(mode: mode) { before in
                sessionTapClick(target: target, cursorBefore: before)
            }
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
        case .axProbe:
            return runTimed(mode: mode) { _ in
                axProbeClick(target: target)
            }
        case .keyEscape:
            return injectEscape(pid: target.pid)
        case .cascade:
            return cascadeClick(target: target)
        }
    }

    public func injectEscape(pid: pid_t) -> InjectResult {
        runTimed(mode: .keyEscape) { _ in
            keyEscape(pid: pid)
        }
    }

    private func sessionTapClick(target: InjectionTarget, cursorBefore: CGPoint) -> (Bool, String) {
        let point = target.clickPointQuartz
        guard let down = makeMouseEvent(type: .leftMouseDown, at: point, windowID: target.windowID),
              let up = makeMouseEvent(type: .leftMouseUp, at: point, windowID: target.windowID) else {
            return (false, "eventCreateFailed")
        }
        down.post(tap: .cgSessionEventTap)
        up.post(tap: .cgSessionEventTap)
        let restoreQuartz = TargetResolver.appKitToQuartz(cursorBefore)
        CGWarpMouseCursorPosition(restoreQuartz)
        return (true, "sessionTap+warpRestore")
    }

    private func postToPidClick(target: InjectionTarget) -> (Bool, String) {
        let point = target.clickPointQuartz
        guard let down = makeMouseEvent(type: .leftMouseDown, at: point, windowID: target.windowID),
              let up = makeMouseEvent(type: .leftMouseUp, at: point, windowID: target.windowID) else {
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
        let point = target.clickPointQuartz
        guard let down = makeMouseEvent(type: .leftMouseDown, at: point, windowID: target.windowID),
              let up = makeMouseEvent(type: .leftMouseUp, at: point, windowID: target.windowID) else {
            return (false, "eventCreateFailed")
        }
        let okDown = SkyLightBridge.shared.post(down, to: target.pid)
        let okUp = SkyLightBridge.shared.post(up, to: target.pid)
        return (okDown && okUp, okDown && okUp ? "SLEventPostToPid" : "skyLightPostFailed")
    }

    private func hidTapClick(target: InjectionTarget, cursorBefore: CGPoint) -> (Bool, String) {
        let point = target.clickPointQuartz
        var notes: [String] = []

        if preferMouseMovedBeforeHID {
            if let moved = makeMouseEvent(type: .mouseMoved, at: point, windowID: target.windowID) {
                moved.post(tap: .cghidEventTap)
                notes.append("mouseMoved")
            }
        }

        guard let down = makeMouseEvent(type: .leftMouseDown, at: point, windowID: target.windowID),
              let up = makeMouseEvent(type: .leftMouseUp, at: point, windowID: target.windowID) else {
            return (false, "eventCreateFailed")
        }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        notes.append("hidDownUp")

        if restoreCursorAfterHID {
            let restoreQuartz = TargetResolver.appKitToQuartz(cursorBefore)
            CGWarpMouseCursorPosition(restoreQuartz)
            notes.append("warpRestore")
        }
        return (true, notes.joined(separator: "+"))
    }

    private func axProbeClick(target: InjectionTarget) -> (Bool, String) {
        let systemWide = AXUIElementCreateSystemWide()
        var elementRef: AXUIElement?
        let status = AXUIElementCopyElementAtPosition(
            systemWide,
            Float(target.clickPointAppKit.x),
            Float(target.clickPointAppKit.y),
            &elementRef
        )

        guard status == .success, let element = elementRef else {
            return (false, "noElementAtPosition axStatus=\(status.rawValue)")
        }

        var roleValue: AnyObject?
        var titleValue: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue)
        AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleValue)
        let role = roleValue as? String ?? "?"
        let title = titleValue as? String ?? ""

        var actionsRef: CFArray?
        AXUIElementCopyActionNames(element, &actionsRef)
        let actions = (actionsRef as? [String]) ?? []

        InjectLogger.log(.inject, "axProbe role=\(role) title=\(title) actions=\(actions.joined(separator: ","))")

        if actions.contains(kAXPressAction as String) {
            let press = AXUIElementPerformAction(element, kAXPressAction as CFString)
            let ok = press == .success
            return (ok, "AXPress role=\(role) title=\(title) status=\(press.rawValue)")
        }

        return (false, "noAXPress role=\(role) title=\(title) actions=\(actions.joined(separator: ","))")
    }

    private func keyEscape(pid: pid_t) -> (Bool, String) {
        let escapeKey: CGKeyCode = 0x35
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: escapeKey, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: escapeKey, keyDown: false) else {
            return (false, "eventCreateFailed")
        }
        down.postToPid(pid)
        up.postToPid(pid)
        return (true, "escapePostToPid")
    }

    private func cascadeClick(target: InjectionTarget) -> InjectResult {
        let before = NSEvent.mouseLocation
        let start = CFAbsoluteTimeGetCurrent()
        var steps: [String] = []

        let pidResult = postToPidClick(target: target)
        steps.append("postToPid=\(pidResult.0 ? "ok" : "fail"):\(pidResult.1)")
        if pidResult.0 {
            return finishCascade(steps: steps, posted: true, before: before, start: start)
        }

        let sky = skyLightClick(target: target)
        steps.append("skyLight=\(sky.0 ? "ok" : "fail"):\(sky.1)")
        if sky.0 {
            return finishCascade(steps: steps, posted: true, before: before, start: start)
        }

        let hid = hidTapClick(target: target, cursorBefore: before)
        steps.append("hidTap=\(hid.0 ? "ok" : "fail"):\(hid.1)")
        return finishCascade(steps: steps, posted: hid.0, before: before, start: start)
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

    private func makeMouseEvent(type: CGEventType, at point: CGPoint, windowID: CGWindowID?) -> CGEvent? {
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
