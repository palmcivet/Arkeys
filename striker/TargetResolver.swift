import Foundation
import AppKit
import ApplicationServices

struct InjectionTarget {
    let pid: pid_t
    let appName: String
    let windowFrame: CGRect
    let windowID: CGWindowID?
    /// Screen coordinates in AppKit space (origin bottom-left), matching NSEvent.mouseLocation / NSWindow.
    let clickPointAppKit: CGPoint
    /// Screen coordinates in Quartz/CGEvent space (origin top-left of global desktop).
    let clickPointQuartz: CGPoint

    var logLine: String {
        let wid = windowID.map(String.init) ?? "nil"
        return "app=\(appName) pid=\(pid) frame=\(NSStringFromRect(windowFrame)) clickAppKit=\(InjectLogger.formatPoint(clickPointAppKit)) clickQuartz=\(InjectLogger.formatPoint(clickPointQuartz)) windowID=\(wid)"
    }
}

enum TargetResolver {
    /// Resolves the frontmost app's focused window and converts window-relative offsets to screen points.
    /// `relativeX/Y` are measured from the window's top-left in points (as in README).
    static func resolveFrontmost(relativeX: Int, relativeY: Int) -> InjectionTarget? {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            InjectLogger.log(.target, "no frontmost application")
            return nil
        }

        let pid = app.processIdentifier
        let appName = app.localizedName ?? "Unknown"
        let axApp = AXUIElementCreateApplication(pid)

        var windowRef: AnyObject?
        let winResult = AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &windowRef)
        guard winResult == .success, let focusedWindow = windowRef else {
            InjectLogger.log(.target, "no focused window app=\(appName) pid=\(pid) axResult=\(winResult.rawValue)")
            return nil
        }

        let axWindow = focusedWindow as! AXUIElement

        var positionValue: AnyObject?
        var sizeValue: AnyObject?
        AXUIElementCopyAttributeValue(axWindow, kAXPositionAttribute as CFString, &positionValue)
        AXUIElementCopyAttributeValue(axWindow, kAXSizeAttribute as CFString, &sizeValue)

        var position = CGPoint.zero
        var size = CGSize.zero
        if let positionValue {
            AXValueGetValue(positionValue as! AXValue, .cgPoint, &position)
        }
        if let sizeValue {
            AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        }

        // AX position/size use AppKit coordinates (origin bottom-left).
        let frame = CGRect(origin: position, size: size)

        // README coords are relative to window top-left.
        let clickAppKit = CGPoint(
            x: frame.origin.x + CGFloat(relativeX),
            y: frame.origin.y + frame.size.height - CGFloat(relativeY)
        )

        let clickQuartz = appKitToQuartz(clickAppKit)
        let windowID = resolveWindowID(pid: pid, frame: frame)

        let target = InjectionTarget(
            pid: pid,
            appName: appName,
            windowFrame: frame,
            windowID: windowID,
            clickPointAppKit: clickAppKit,
            clickPointQuartz: clickQuartz
        )
        InjectLogger.log(.target, target.logLine)
        return target
    }

    /// Converts AppKit global point to CGEvent/Quartz global point.
    static func appKitToQuartz(_ point: CGPoint) -> CGPoint {
        let primaryMaxY = NSScreen.screens.map(\.frame.maxY).max() ?? 0
        return CGPoint(x: point.x, y: primaryMaxY - point.y)
    }

    static func quartzToAppKit(_ point: CGPoint) -> CGPoint {
        let primaryMaxY = NSScreen.screens.map(\.frame.maxY).max() ?? 0
        return CGPoint(x: point.x, y: primaryMaxY - point.y)
    }

    private static func resolveWindowID(pid: pid_t, frame: CGRect) -> CGWindowID? {
        guard let infoList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        let matches = infoList.filter { info in
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t, ownerPID == pid else { return false }
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0 else { return false }
            return true
        }

        let axQuartz = appKitFrameToQuartz(frame)
        var best: (CGWindowID, CGFloat)?

        for info in matches {
            guard let number = info[kCGWindowNumber as String] as? CGWindowID else { continue }
            guard let boundsDict = info[kCGWindowBounds as String] as? [String: CGFloat] else {
                if best == nil { best = (number, 0) }
                continue
            }
            let bounds = CGRect(
                x: boundsDict["X"] ?? 0,
                y: boundsDict["Y"] ?? 0,
                width: boundsDict["Width"] ?? 0,
                height: boundsDict["Height"] ?? 0
            )
            let overlap = bounds.intersection(axQuartz).area
            if best == nil || overlap > best!.1 {
                best = (number, overlap)
            }
        }

        return best?.0
    }

    private static func appKitFrameToQuartz(_ frame: CGRect) -> CGRect {
        let topLeft = appKitToQuartz(CGPoint(x: frame.minX, y: frame.maxY))
        return CGRect(x: topLeft.x, y: topLeft.y, width: frame.width, height: frame.height)
    }
}

private extension CGRect {
    var area: CGFloat { max(0, width) * max(0, height) }
}
