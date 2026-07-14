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

    private func cascadeClick(target: InjectionTarget) -> InjectResult {
        let before = NSEvent.mouseLocation
        let start = CFAbsoluteTimeGetCurrent()
        var steps: [String] = []

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

    /// Cascade step log: `postToPid=ok` or `postToPid=fail(eventCreateFailed)`.
    /// Avoids redundant `postToPid=ok:postToPid` when the detail string just repeats the route name.
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
