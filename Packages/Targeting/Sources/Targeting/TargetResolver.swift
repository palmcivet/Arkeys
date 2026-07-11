import Foundation
import AppKit
import ApplicationServices

public struct InjectionTarget: Sendable {
    public let pid: pid_t
    public let appName: String
    public let bundleIdentifier: String?
    public let windowFrame: CGRect
    public let windowID: CGWindowID?
    /// Screen coordinates in AppKit space (origin bottom-left).
    public let clickPointAppKit: CGPoint
    /// Screen coordinates in Quartz/CGEvent space (origin top-left).
    public let clickPointQuartz: CGPoint

    public init(
        pid: pid_t,
        appName: String,
        bundleIdentifier: String?,
        windowFrame: CGRect,
        windowID: CGWindowID?,
        clickPointAppKit: CGPoint,
        clickPointQuartz: CGPoint
    ) {
        self.pid = pid
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.windowFrame = windowFrame
        self.windowID = windowID
        self.clickPointAppKit = clickPointAppKit
        self.clickPointQuartz = clickPointQuartz
    }

    public var logLine: String {
        let wid = windowID.map(String.init) ?? "nil"
        return "app=\(appName) pid=\(pid) frame=\(NSStringFromRect(windowFrame)) clickAppKit=\(formatPoint(clickPointAppKit)) clickQuartz=\(formatPoint(clickPointQuartz)) windowID=\(wid)"
    }
}

public enum TargetResolver {
    public static func resolveFrontmost(relativeX: Double, relativeY: Double) -> InjectionTarget? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        return resolve(app: app, relativeX: relativeX, relativeY: relativeY)
    }

    /// `relativeX/Y` are fractions 0...1 from the window's top-left.
    public static func resolve(app: NSRunningApplication, relativeX: Double, relativeY: Double) -> InjectionTarget? {
        let pid = app.processIdentifier
        let appName = app.localizedName ?? "Unknown"
        let axApp = AXUIElementCreateApplication(pid)

        var windowRef: AnyObject?
        let winResult = AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &windowRef)
        guard winResult == .success, let focusedWindow = windowRef else {
            return nil
        }

        let axWindow = focusedWindow as! AXUIElement
        guard let frame = windowFrame(axWindow: axWindow) else { return nil }

        let clickAppKit = CGPoint(
            x: frame.origin.x + frame.size.width * relativeX,
            y: frame.origin.y + frame.size.height * (1.0 - relativeY)
        )
        let clickQuartz = appKitToQuartz(clickAppKit)
        let windowID = resolveWindowID(pid: pid, frame: frame)

        return InjectionTarget(
            pid: pid,
            appName: appName,
            bundleIdentifier: app.bundleIdentifier,
            windowFrame: frame,
            windowID: windowID,
            clickPointAppKit: clickAppKit,
            clickPointQuartz: clickQuartz
        )
    }

    /// Absolute point offsets from top-left (legacy PoC units).
    public static func resolveFrontmost(pointOffsetX: Int, pointOffsetY: Int) -> InjectionTarget? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        guard let frame = focusedWindowFrame(for: app) else { return nil }
        let relX = frame.width > 0 ? Double(pointOffsetX) / Double(frame.width) : 0
        let relY = frame.height > 0 ? Double(pointOffsetY) / Double(frame.height) : 0
        return resolve(app: app, relativeX: relX, relativeY: relY)
    }

    public static func focusedWindowFrame(for app: NSRunningApplication) -> CGRect? {
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var windowRef: AnyObject?
        let winResult = AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &windowRef)
        guard winResult == .success, let focusedWindow = windowRef else { return nil }
        return windowFrame(axWindow: focusedWindow as! AXUIElement)
    }

    public static func appKitToQuartz(_ point: CGPoint) -> CGPoint {
        let primaryMaxY = NSScreen.screens.map(\.frame.maxY).max() ?? 0
        return CGPoint(x: point.x, y: primaryMaxY - point.y)
    }

    public static func quartzToAppKit(_ point: CGPoint) -> CGPoint {
        let primaryMaxY = NSScreen.screens.map(\.frame.maxY).max() ?? 0
        return CGPoint(x: point.x, y: primaryMaxY - point.y)
    }

    private static func windowFrame(axWindow: AXUIElement) -> CGRect? {
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
        guard size.width > 0, size.height > 0 else { return nil }
        return CGRect(origin: position, size: size)
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

private func formatPoint(_ point: CGPoint) -> String {
    String(format: "(%.1f,%.1f)", point.x, point.y)
}
