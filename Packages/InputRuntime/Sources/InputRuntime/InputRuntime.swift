import Foundation
import AppKit
import Combine
import KeymapCore
import Injection
import Targeting

@MainActor
public final class InputRuntime: ObservableObject {
    @Published public var targetBundleID: String?
    @Published public var targetAppName: String = "(none)"
    @Published public var keymap: CanonicalKeymap = CanonicalKeymap()
    @Published public var injectMode: InjectMode = .postToPid
    @Published public var preferMouseMovedBeforeHID: Bool = true
    @Published public var restoreCursorAfterHID: Bool = true
    @Published public var isEnabled: Bool = true
    @Published public var isEditing: Bool = false
    @Published public var isListening: Bool = false
    @Published public var capabilitySummary: String = ""
    @Published public var lastInjectSummary: String = "(none yet)"
    @Published public var keymapSummary: String = "(empty)"

    public var onEditorKeyDown: ((UInt16, String) -> Void)?

    private var globalKeyMonitor: Any?
    private var localKeyMonitor: Any?
    private let injector = EventInjector()
    private let store = KeymapStore()
    private var didStart = false

    public init() {
        DispatchQueue.main.async { [weak self] in
            self?.startIfNeeded()
        }
    }

    deinit {
        // Monitors removed best-effort; NSEvent APIs are main-thread.
    }

    public func startIfNeeded() {
        guard !didStart else { return }
        didStart = true
        let report = CapabilityProbe.run(promptAccessibility: true)
        capabilitySummary = report.summaryLine
        startMonitoring()
    }

    public func startMonitoring() {
        stopMonitoring()

        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor in
                self?.handleKeyEvent(event, source: "global")
            }
        }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor in
                self?.handleKeyEvent(event, source: "local")
            }
            return event
        }

        isListening = (globalKeyMonitor != nil)
        if globalKeyMonitor == nil {
            InjectLogger.log(.capability, "global key monitor FAILED — enable Accessibility")
        } else {
            InjectLogger.log(.capability, "global+local key monitors started")
        }
    }

    public func stopMonitoring() {
        if let globalKeyMonitor {
            NSEvent.removeMonitor(globalKeyMonitor)
            self.globalKeyMonitor = nil
        }
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
            self.localKeyMonitor = nil
        }
        isListening = false
    }

    public func bindFrontmostApp() {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let bundleID = app.bundleIdentifier else {
            InjectLogger.log(.target, "cannot bind frontmost — missing bundle id")
            return
        }
        // Avoid binding Striker itself when settings are frontmost.
        if bundleID == Bundle.main.bundleIdentifier {
            InjectLogger.log(.target, "skip binding Striker itself")
            return
        }
        targetBundleID = bundleID
        targetAppName = app.localizedName ?? bundleID
        if let loaded = store.load(bundleID: bundleID) {
            keymap = loaded
        } else {
            keymap = CanonicalKeymap(targetHint: bundleID, source: .striker(version: "1.0.0"))
        }
        refreshKeymapSummary()
        InjectLogger.log(.target, "bound target=\(targetAppName) id=\(bundleID)")
    }

    public func saveKeymap() {
        guard let targetBundleID else { return }
        do {
            try store.save(keymap, bundleID: targetBundleID)
            refreshKeymapSummary()
            InjectLogger.log(.target, "saved keymap for \(targetBundleID)")
        } catch {
            InjectLogger.log(.target, "save failed: \(error.localizedDescription)")
        }
    }

    public func applyImportedKeymap(_ imported: CanonicalKeymap) {
        var map = imported
        if map.targetHint == nil {
            map.targetHint = targetBundleID
        }
        keymap = map
        if let hint = map.targetHint, targetBundleID == nil {
            targetBundleID = hint
            targetAppName = hint
        }
        saveKeymap()
        refreshKeymapSummary()
    }

    public func clearKeymap() {
        keymap = CanonicalKeymap(targetHint: targetBundleID, source: .striker(version: "1.0.0"))
        if let targetBundleID {
            store.delete(bundleID: targetBundleID)
        }
        refreshKeymapSummary()
    }

    public func refreshCapability() {
        let report = CapabilityProbe.run(promptAccessibility: false)
        capabilitySummary = report.summaryLine
        didStart = false
        startIfNeeded()
    }

    public func fireClick(relativeX: Double, relativeY: Double) {
        syncInjectorOptions()
        guard let target = TargetResolver.resolveFrontmost(relativeX: relativeX, relativeY: relativeY) else {
            lastInjectSummary = "resolve failed"
            return
        }
        NotificationCenter.default.post(name: .showClickOverlay, object: target.clickPointAppKit)
        let result = injector.injectClick(mode: injectMode, target: target)
        lastInjectSummary = result.summary
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            NotificationCenter.default.post(name: .hideClickOverlay, object: nil)
        }
    }

    public func fireEscape() {
        syncInjectorOptions()
        guard let app = NSWorkspace.shared.frontmostApplication else {
            lastInjectSummary = "no frontmost app for escape"
            return
        }
        let result = injector.injectEscape(pid: app.processIdentifier)
        lastInjectSummary = result.summary
    }

    private func handleKeyEvent(_ event: NSEvent, source: String) {
        if event.isARepeat { return }

        let keyCode = event.keyCode
        let chars = event.charactersIgnoringModifiers ?? ""
        InjectLogger.log(.inject, "keyDown source=\(source) keyCode=\(keyCode) chars=\(chars.debugDescription)")

        if isEditing {
            let name = CarbonKeyNames.name(for: keyCode)
            onEditorKeyDown?(keyCode, name)
            return
        }

        guard isEnabled else { return }
        guard let targetBundleID else { return }
        guard let front = NSWorkspace.shared.frontmostApplication,
              front.bundleIdentifier == targetBundleID else {
            return
        }

        // Prefer bare keys: ignore when command/option/control/shift held.
        let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard mods.isEmpty else { return }

        guard let button = keymap.button(matchingKeyCode: keyCode) else { return }
        InjectLogger.log(.inject, "matched binding \(button.key.name) @ (\(button.transform.x),\(button.transform.y))")
        fireClick(relativeX: button.transform.x, relativeY: button.transform.y)
    }

    private func syncInjectorOptions() {
        injector.preferMouseMovedBeforeHID = preferMouseMovedBeforeHID
        injector.restoreCursorAfterHID = restoreCursorAfterHID
    }

    private func refreshKeymapSummary() {
        keymapSummary = keymap.summaryLine
    }
}

public extension Notification.Name {
    static let showClickOverlay = Notification.Name("showClickOverlay")
    static let hideClickOverlay = Notification.Name("hideClickOverlay")
    static let keymapEditorDidFinish = Notification.Name("keymapEditorDidFinish")
}
