import Foundation
import ApplicationServices
import ObjectiveC

/// Soft-loads SkyLight private symbols. Never hard-link the framework.
final class SkyLightBridge {
    static let shared = SkyLightBridge()

    private typealias SLEventPostToPidFn = @convention(c) (CGEvent?, pid_t) -> Void

    private let handle: UnsafeMutableRawPointer?
    private let postToPidFn: SLEventPostToPidFn?
    private(set) var hasAuthMessage: Bool = false

    var isAvailable: Bool { postToPidFn != nil }

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

    /// Posts a CGEvent via SkyLight's WindowServer trust path.
    /// Returns false if the symbol is missing.
    @discardableResult
    func post(_ event: CGEvent, to pid: pid_t) -> Bool {
        guard let postToPidFn else {
            InjectLogger.log(.inject, "skyLightUnavailable symbol=SLEventPostToPid")
            return false
        }

        // Auth envelope only exists usefully on macOS 15+; gated in CapabilityProbe.
        // Plain SLEventPostToPid is the path used for PoC on 14+.
        _ = hasAuthMessage
        postToPidFn(event, pid)
        return true
    }

    private static func resolveAuthMessageSupport() -> Bool {
        guard #available(macOS 15.0, *) else { return false }

        guard let cls = NSClassFromString("SLSEventAuthenticationMessage") as? NSObject.Type else {
            return false
        }
        let sel = NSSelectorFromString("messageWithEventRecord:pid:version:")
        // class_respondsToSelector checks the metaclass for factory methods.
        return cls.responds(to: sel)
    }
}
