import Foundation
import ApplicationServices
import AppKit

struct CapabilityReport {
    let osVersion: String
    let accessibilityTrusted: Bool
    let eventTapCreatable: Bool
    let skyLightPostToPid: Bool
    let authMessage: Bool
    let sandboxEnabled: Bool

    var summaryLine: String {
        "[Striker][capability] os=\(osVersion) ax=\(accessibilityTrusted) tap=\(eventTapCreatable ? "ok" : "fail") skyLight=SLEventPostToPid:\(skyLightPostToPid ? "yes" : "no") authMsg=\(authMessage ? "yes" : "no") sandbox=\(sandboxEnabled)"
    }
}

enum CapabilityProbe {
    static func run(promptAccessibility: Bool = true) -> CapabilityReport {
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString

        let axTrusted: Bool
        if promptAccessibility {
            let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as NSString: true]
            axTrusted = AXIsProcessTrustedWithOptions(options)
        } else {
            axTrusted = AXIsProcessTrusted()
        }

        let tapOK = canCreateKeyDownTap()
        let sky = SkyLightBridge.shared
        let sandbox = isAppSandboxed()

        let report = CapabilityReport(
            osVersion: osVersion,
            accessibilityTrusted: axTrusted,
            eventTapCreatable: tapOK,
            skyLightPostToPid: sky.isAvailable,
            authMessage: sky.hasAuthMessage,
            sandboxEnabled: sandbox
        )
        print(report.summaryLine)
        return report
    }

    private static func canCreateKeyDownTap() -> Bool {
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, _, event, _ in Unmanaged.passUnretained(event) },
            userInfo: nil
        ) else {
            return false
        }
        CFMachPortInvalidate(tap)
        return true
    }

    private static func isAppSandboxed() -> Bool {
        ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
            || Bundle.main.object(forInfoDictionaryKey: "com.apple.security.app-sandbox") as? Bool == true
    }
}
