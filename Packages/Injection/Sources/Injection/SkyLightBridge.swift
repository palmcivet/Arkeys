import Foundation
import ApplicationServices
import ObjectiveC

/// Soft-loads SkyLight private symbols. Never hard-link the framework.
public final class SkyLightBridge: @unchecked Sendable {
    public static let shared = SkyLightBridge()

    private typealias SLEventPostToPidFn = @convention(c) (CGEvent?, pid_t) -> Void

    private let handle: UnsafeMutableRawPointer?
    private let postToPidFn: SLEventPostToPidFn?
    private(set) public var hasAuthMessage: Bool = false

    public var isAvailable: Bool { postToPidFn != nil }

    private init() {
        let path = "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"
        handle = dlopen(path, RTLD_LAZY)

        if let handle, let sym = dlsym(handle, "SLEventPostToPid") {
            postToPidFn = unsafeBitCast(sym, to: SLEventPostToPidFn.self)
        } else {
            postToPidFn = nil
        }

        hasAuthMessage = Self.resolveAuthMessageSupport()
    }

    @discardableResult
    public func post(_ event: CGEvent, to pid: pid_t) -> Bool {
        guard let postToPidFn else {
            InjectLogger.log(.inject, "skyLightUnavailable symbol=SLEventPostToPid")
            return false
        }
        postToPidFn(event, pid)
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
