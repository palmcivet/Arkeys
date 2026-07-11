import Cocoa
import ApplicationServices
import Carbon.HIToolbox

class InputMonitor: ObservableObject {
    @Published var hotkey: String = "K"
    @Published var escapeHotkey: String = "J"
    @Published var clickX: Int = 100
    @Published var clickY: Int = 100
    @Published var injectMode: InjectMode = .postToPid
    @Published var preferMouseMovedBeforeHID: Bool = true
    @Published var restoreCursorAfterHID: Bool = true
    @Published var capabilitySummary: String = ""
    @Published var lastInjectSummary: String = "(none yet)"
    @Published var isListening: Bool = false

    private var globalKeyMonitor: Any?
    private var localKeyMonitor: Any?
    private let injector = EventInjector()
    private var didStart = false

    init() {
        // Start on next main-loop turn so NSApplication exists.
        DispatchQueue.main.async { [weak self] in
            self?.startIfNeeded()
        }
    }

    deinit {
        stopMonitoring()
    }

    /// Safe to call multiple times; only the first successful start sticks.
    func startIfNeeded() {
        guard !didStart else { return }
        didStart = true

        let report = CapabilityProbe.run(promptAccessibility: true)
        capabilitySummary = report.summaryLine

        startMonitoring()
    }

    func startMonitoring() {
        stopMonitoring()

        // Global: other apps frontmost. Local: Striker itself frontmost.
        // CGEvent taps often yield NSEvents with nil `characters`; keyCode matching is required.
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyEvent(event, source: "global")
        }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyEvent(event, source: "local")
            return event
        }

        isListening = (globalKeyMonitor != nil)
        if globalKeyMonitor == nil {
            InjectLogger.log(.capability, "global key monitor FAILED — enable Accessibility for Striker, then Re-probe / relaunch")
        } else {
            InjectLogger.log(.capability, "global+local key monitors started (K/J via keyCode)")
        }
        if localKeyMonitor == nil {
            InjectLogger.log(.capability, "local key monitor FAILED")
        }
    }

    func stopMonitoring() {
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

    func fireClick() {
        syncInjectorOptions()
        guard let target = TargetResolver.resolveFrontmost(relativeX: clickX, relativeY: clickY) else {
            lastInjectSummary = "resolve failed — see console"
            return
        }

        NotificationCenter.default.post(name: .showClickOverlay, object: target.clickPointAppKit)

        let result: InjectResult
        if injectMode == .keyEscape {
            result = injector.injectEscape(pid: target.pid)
        } else {
            result = injector.injectClick(mode: injectMode, target: target)
        }
        lastInjectSummary = result.summary

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            NotificationCenter.default.post(name: .hideClickOverlay, object: nil)
        }
    }

    func fireEscape() {
        syncInjectorOptions()
        guard let app = NSWorkspace.shared.frontmostApplication else {
            lastInjectSummary = "no frontmost app for escape"
            InjectLogger.log(.target, "no frontmost application for escape")
            return
        }
        InjectLogger.log(.target, "escape → \(app.localizedName ?? "?") pid=\(app.processIdentifier)")
        let result = injector.injectEscape(pid: app.processIdentifier)
        lastInjectSummary = result.summary
    }

    func refreshCapability() {
        let report = CapabilityProbe.run(promptAccessibility: false)
        capabilitySummary = report.summaryLine
        // Recreate monitors after permission changes.
        didStart = false
        startIfNeeded()
    }

    private func syncInjectorOptions() {
        injector.preferMouseMovedBeforeHID = preferMouseMovedBeforeHID
        injector.restoreCursorAfterHID = restoreCursorAfterHID
    }

    private func handleKeyEvent(_ event: NSEvent, source: String) {
        if event.isARepeat { return }

        let keyCode = Int(event.keyCode)
        let chars = event.charactersIgnoringModifiers ?? ""
        InjectLogger.log(.inject, "keyDown source=\(source) keyCode=\(keyCode) chars=\(chars.debugDescription)")

        if keyCode == kVK_Escape, injectMode == .keyEscape {
            InjectLogger.log(.inject, "physical Escape matched (mode=keyEscape)")
            fireEscape()
            return
        }

        if matchesHotkey(hotkey, keyCode: keyCode, chars: chars) {
            InjectLogger.log(.inject, "click hotkey '\(hotkey)' mode=\(injectMode.rawValue)")
            fireClick()
            return
        }

        if !escapeHotkey.isEmpty, matchesHotkey(escapeHotkey, keyCode: keyCode, chars: chars) {
            InjectLogger.log(.inject, "escape hotkey '\(escapeHotkey)'")
            fireEscape()
            return
        }
    }

    /// Prefer ANSI keyCode for A–Z; fall back to character compare.
    private func matchesHotkey(_ hotkey: String, keyCode: Int, chars: String) -> Bool {
        let trimmed = hotkey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let scalar = trimmed.uppercased().unicodeScalars.first else { return false }

        if let expected = Self.ansiKeyCode(forLatinLetter: Character(scalar)) {
            if keyCode == expected { return true }
        }

        guard let pressed = chars.uppercased().first else { return false }
        return pressed == Character(scalar)
    }

    private static func ansiKeyCode(forLatinLetter letter: Character) -> Int? {
        switch letter {
        case "A": return kVK_ANSI_A
        case "B": return kVK_ANSI_B
        case "C": return kVK_ANSI_C
        case "D": return kVK_ANSI_D
        case "E": return kVK_ANSI_E
        case "F": return kVK_ANSI_F
        case "G": return kVK_ANSI_G
        case "H": return kVK_ANSI_H
        case "I": return kVK_ANSI_I
        case "J": return kVK_ANSI_J
        case "K": return kVK_ANSI_K
        case "L": return kVK_ANSI_L
        case "M": return kVK_ANSI_M
        case "N": return kVK_ANSI_N
        case "O": return kVK_ANSI_O
        case "P": return kVK_ANSI_P
        case "Q": return kVK_ANSI_Q
        case "R": return kVK_ANSI_R
        case "S": return kVK_ANSI_S
        case "T": return kVK_ANSI_T
        case "U": return kVK_ANSI_U
        case "V": return kVK_ANSI_V
        case "W": return kVK_ANSI_W
        case "X": return kVK_ANSI_X
        case "Y": return kVK_ANSI_Y
        case "Z": return kVK_ANSI_Z
        default: return nil
        }
    }
}
