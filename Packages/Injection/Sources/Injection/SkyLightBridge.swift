import Foundation
import ApplicationServices
import ObjectiveC
import Targeting

/// Soft-loads SkyLight private symbols. Never hard-link the framework.
///
/// On current macOS, `CGEventPostToPid` is a re-export of `SLEventPostToPid`
/// — same implementation. The C ABI is `(pid_t, CGEventRef)`, **not**
/// `(CGEventRef, pid_t)` — reversing the parameters causes `EXC_BAD_ACCESS`.
public final class SkyLightBridge: @unchecked Sendable {
    public static let shared = SkyLightBridge()

    /// Matches `CGEventPostToPid(pid_t, CGEventRef)`.
    private typealias SLEventPostToPidFn = @convention(c) (pid_t, CGEvent?) -> Void
    private typealias CGEventSetWindowLocationFn = @convention(c) (CGEvent?, CGPoint) -> Void

    private let handle: UnsafeMutableRawPointer?
    private let postToPidFn: SLEventPostToPidFn?
    private let setWindowLocationFn: CGEventSetWindowLocationFn?
    private(set) public var hasAuthMessage: Bool = false

    public var isAvailable: Bool { postToPidFn != nil }
    public var hasSetWindowLocation: Bool { setWindowLocationFn != nil }

    private init() {
        let path = "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"
        handle = dlopen(path, RTLD_LAZY)

        let rtldDefault = UnsafeMutableRawPointer(bitPattern: -2)

        if let handle, let sym = dlsym(handle, "SLEventPostToPid") {
            postToPidFn = unsafeBitCast(sym, to: SLEventPostToPidFn.self)
        } else {
            postToPidFn = nil
        }

        // CGEventSetWindowLocation is a private setter that tells WindowServer
        // the window-local coordinates of the event. Resolvable via RTLD_DEFAULT
        // (it lives in CoreGraphics) or from SkyLight.
        if let sym = dlsym(rtldDefault, "CGEventSetWindowLocation")
            ?? (handle.flatMap { dlsym($0, "CGEventSetWindowLocation") }) {
            setWindowLocationFn = unsafeBitCast(sym, to: CGEventSetWindowLocationFn.self)
        } else {
            setWindowLocationFn = nil
        }

        hasAuthMessage = Self.resolveAuthMessageSupport()
    }

    @discardableResult
    public func post(_ event: CGEvent, to pid: pid_t) -> Bool {
        guard let postToPidFn else {
            AppLog.log(.inject, "skyLightUnavailable symbol=SLEventPostToPid")
            return false
        }
        postToPidFn(pid, event)
        return true
    }

    @discardableResult
    public func setWindowLocation(_ event: CGEvent, to point: CGPoint) -> Bool {
        guard let setWindowLocationFn else { return false }
        setWindowLocationFn(event, point)
        return true
    }

    private static func resolveAuthMessageSupport() -> Bool {
        guard #available(macOS 15.0, *) else { return false }
        guard let cls = NSClassFromString("SLSEventAuthenticationMessage") as? NSObject.Type else {
            return false
        }
        let sel = NSSelectorFromString("messageWithEventRecord:pid:version:")
        return cls.responds(to: sel)
    }
}
