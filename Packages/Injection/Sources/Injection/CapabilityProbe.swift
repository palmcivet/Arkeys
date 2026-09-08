import Foundation
import ApplicationServices
import AppKit
import Targeting

public struct CapabilityReport: Sendable {
    public let osVersion: String
    public let accessibilityTrusted: Bool
    public let eventTapCreatable: Bool
    public let skyLightPostToPid: Bool
    public let setWindowLocation: Bool
    public let authMessage: Bool

    public var summaryLine: String {
        "os=\(osVersion) ax=\(accessibilityTrusted) tap=\(eventTapCreatable ? "ok" : "fail") "
        + "skyLight=\(skyLightPostToPid ? "yes" : "no") windowLoc=\(setWindowLocation ? "yes" : "no")"
    }
}

public enum CapabilityProbe {
    public static func run(promptAccessibility: Bool = true) -> CapabilityReport {
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString

        let axTrusted: Bool
        if promptAccessibility {
            // Registers this process with TCC and may present the system
            // "Accessibility Access" dialog. Opening System Settings alone does not.
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            axTrusted = AXIsProcessTrustedWithOptions(options)
        } else {
            axTrusted = AXIsProcessTrusted()
        }

        let tapOK = canCreateKeyDownTap()
        let sky = SkyLightBridge.shared

        let report = CapabilityReport(
            osVersion: osVersion,
            accessibilityTrusted: axTrusted,
            eventTapCreatable: tapOK,
            skyLightPostToPid: sky.isAvailable,
            setWindowLocation: sky.hasSetWindowLocation,
            authMessage: sky.hasAuthMessage
        )
        AppLog.log(.capability, report.summaryLine)
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
}
