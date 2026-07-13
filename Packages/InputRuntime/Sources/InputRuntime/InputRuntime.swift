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
    @Published public var schemes: [KeymapSchemeMeta] = []
    @Published public var activeSchemeID: UUID?
    @Published public var injectMode: InjectMode = .cascade {
        didSet { persistSettings() }
    }
    @Published public var preferMouseMovedBeforeHID: Bool = true {
        didSet { persistSettings() }
    }
    @Published public var restoreCursorAfterHID: Bool = true {
        didSet { persistSettings() }
    }
    @Published public var isEnabled: Bool = true {
        didSet { persistSettings() }
    }
    @Published public var showMenuBarIcon: Bool = true {
        didSet { persistSettings() }
    }
    @Published public var isEditing: Bool = false
    @Published public var isListening: Bool = false
    @Published public var capability: CapabilityReport?
    @Published public var capabilitySummary: String = ""
    @Published public var lastInjectSummary: String = ""
    @Published public var lastInjectPosted: Bool?
    @Published public var keymapSummary: String = "(empty)"

    public var onEditorKeyDown: ((UInt16, String) -> Void)?

    private var globalKeyMonitor: Any?
    private var localKeyMonitor: Any?
    private let injector = EventInjector()
    private let store = KeymapStore()
    private let settingsStore = AppSettingsStore()
    private var didStart = false
    private var isRestoringSettings = false
    private var pendingInjectModeRaw: String?

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
        restoreSettings()
        applyCapability(CapabilityProbe.run(promptAccessibility: true))
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

    /// Bind a specific running app as the injection target (focus gate).
    public func bind(app: NSRunningApplication) {
        guard let bundleID = app.bundleIdentifier else {
            InjectLogger.log(.target, "cannot bind — missing bundle id")
            return
        }
        if bundleID == Bundle.main.bundleIdentifier {
            InjectLogger.log(.target, "skip binding Striker itself")
            return
        }
        bind(bundleID: bundleID, appName: app.localizedName ?? bundleID)
    }

    public func bind(bundleID: String, appName: String? = nil) {
        if bundleID == Bundle.main.bundleIdentifier {
            InjectLogger.log(.target, "skip binding Striker itself")
            return
        }
        targetBundleID = bundleID
        targetAppName = appName ?? RunningAppCatalog.runningApplication(bundleID: bundleID)?.localizedName ?? bundleID
        reloadSchemesFromStore()
        persistSettings()
        InjectLogger.log(.target, "bound target=\(targetAppName) id=\(bundleID)")
    }

    /// Create a blank Striker keymap scheme for the current target and persist it.
    @discardableResult
    public func createNewKeymap(name: String = "Untitled") -> Bool {
        guard let targetBundleID else {
            InjectLogger.log(.target, "cannot create keymap — no target")
            return false
        }
        let blank = CanonicalKeymap(targetHint: targetBundleID, source: .striker(version: "1.0.0"))
        do {
            let meta = try store.create(keymap: blank, bundleID: targetBundleID, name: name)
            activeSchemeID = meta.id
            keymap = blank
            refreshSchemesList()
            refreshKeymapSummary()
            InjectLogger.log(.target, "created new empty keymap for \(targetBundleID)")
            return true
        } catch {
            InjectLogger.log(.target, "create failed: \(error.localizedDescription)")
            return false
        }
    }

    public func selectableApps() -> [SelectableApp] {
        RunningAppCatalog.selectableApps()
    }

    public func selectScheme(id: UUID) {
        guard let targetBundleID else { return }
        guard schemes.contains(where: { $0.id == id }) else { return }
        do {
            try store.setActive(schemeID: id, bundleID: targetBundleID)
            activeSchemeID = id
            if let loaded = store.load(bundleID: targetBundleID, schemeID: id) {
                keymap = loaded
            }
            refreshKeymapSummary()
            InjectLogger.log(.target, "selected scheme \(id.uuidString)")
        } catch {
            InjectLogger.log(.target, "select scheme failed: \(error.localizedDescription)")
        }
    }

    public func renameScheme(id: UUID, name: String) {
        guard let targetBundleID else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            try store.rename(schemeID: id, bundleID: targetBundleID, name: trimmed)
            refreshSchemesList()
        } catch {
            InjectLogger.log(.target, "rename failed: \(error.localizedDescription)")
        }
    }

    public func saveKeymap() {
        guard let targetBundleID, let activeSchemeID else { return }
        do {
            try store.save(keymap, bundleID: targetBundleID, schemeID: activeSchemeID)
            refreshSchemesList()
            refreshKeymapSummary()
            InjectLogger.log(.target, "saved keymap for \(targetBundleID) scheme=\(activeSchemeID)")
        } catch {
            InjectLogger.log(.target, "save failed: \(error.localizedDescription)")
        }
    }

    public func applyImportedKeymap(_ imported: CanonicalKeymap, suggestedName: String? = nil) {
        var map = imported
        if map.targetHint == nil {
            map.targetHint = targetBundleID
        }
        if let hint = map.targetHint, targetBundleID == nil {
            targetBundleID = hint
            targetAppName = RunningAppCatalog.runningApplication(bundleID: hint)?.localizedName ?? hint
        }
        guard let targetBundleID else {
            InjectLogger.log(.target, "import failed — no target")
            return
        }
        let name = suggestedName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? "Imported"
        do {
            let meta = try store.create(keymap: map, bundleID: targetBundleID, name: name)
            activeSchemeID = meta.id
            keymap = map
            refreshSchemesList()
            refreshKeymapSummary()
            persistSettings()
        } catch {
            InjectLogger.log(.target, "import save failed: \(error.localizedDescription)")
        }
    }

    /// Delete the currently active scheme (or clear state if none remain).
    public func deleteActiveScheme() {
        guard let targetBundleID else { return }
        guard let activeSchemeID else {
            keymap = CanonicalKeymap(targetHint: targetBundleID, source: .striker(version: "1.0.0"))
            refreshKeymapSummary()
            return
        }
        do {
            try store.delete(schemeID: activeSchemeID, bundleID: targetBundleID)
            reloadSchemesFromStore()
            InjectLogger.log(.target, "deleted scheme \(activeSchemeID)")
        } catch {
            InjectLogger.log(.target, "delete failed: \(error.localizedDescription)")
        }
    }

    public func clearKeymap() {
        deleteActiveScheme()
    }

    public func refreshCapability() {
        applyCapability(CapabilityProbe.run(promptAccessibility: false))
        if !isListening {
            startMonitoring()
        }
    }

    public func fireClick(relativeX: Double, relativeY: Double) {
        syncInjectorOptions()
        guard let target = TargetResolver.resolveFrontmost(relativeX: relativeX, relativeY: relativeY) else {
            lastInjectSummary = "resolve failed"
            lastInjectPosted = false
            return
        }
        NotificationCenter.default.post(name: .showClickOverlay, object: target.clickPointAppKit)
        let result = injector.injectClick(mode: injectMode, target: target)
        lastInjectSummary = result.summary
        lastInjectPosted = result.posted
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            NotificationCenter.default.post(name: .hideClickOverlay, object: nil)
        }
    }

    private func applyCapability(_ report: CapabilityReport) {
        capability = report
        capabilitySummary = report.summaryLine
        let raw = pendingInjectModeRaw ?? injectMode.rawValue
        let resolved = InjectMode.resolvedProductMode(raw: raw, report: report)
        pendingInjectModeRaw = nil
        if injectMode != resolved {
            injectMode = resolved
        }
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
        let schemeName = schemes.first(where: { $0.id == activeSchemeID })?.name ?? "(none)"
        keymapSummary = "scheme=\(schemeName) \(keymap.summaryLine)"
    }

    private func refreshSchemesList() {
        guard let targetBundleID else {
            schemes = []
            return
        }
        let manifest = store.loadManifest(bundleID: targetBundleID)
        schemes = manifest.schemes
        activeSchemeID = manifest.activeMeta?.id
    }

    private func reloadSchemesFromStore() {
        guard let targetBundleID else {
            schemes = []
            activeSchemeID = nil
            keymap = CanonicalKeymap()
            refreshKeymapSummary()
            return
        }
        refreshSchemesList()
        if let active = store.loadActive(bundleID: targetBundleID) {
            activeSchemeID = active.meta.id
            keymap = active.keymap
        } else {
            activeSchemeID = nil
            keymap = CanonicalKeymap(targetHint: targetBundleID, source: .striker(version: "1.0.0"))
        }
        refreshKeymapSummary()
    }

    private func restoreSettings() {
        isRestoringSettings = true
        defer { isRestoringSettings = false }
        let settings = settingsStore.load()
        isEnabled = settings.isEnabled
        preferMouseMovedBeforeHID = settings.preferMouseMovedBeforeHID
        restoreCursorAfterHID = settings.restoreCursorAfterHID
        showMenuBarIcon = settings.showMenuBarIcon
        pendingInjectModeRaw = settings.injectModeRaw
        injectMode = InjectMode.resolvedProductMode(raw: settings.injectModeRaw, report: nil)
        if let bundleID = settings.lastTargetBundleID {
            bind(bundleID: bundleID, appName: settings.lastTargetAppName)
        }
    }

    private func persistSettings() {
        guard !isRestoringSettings else { return }
        let settings = AppSettings(
            lastTargetBundleID: targetBundleID,
            lastTargetAppName: targetAppName == "(none)" ? nil : targetAppName,
            isEnabled: isEnabled,
            injectModeRaw: injectMode.rawValue,
            preferMouseMovedBeforeHID: preferMouseMovedBeforeHID,
            restoreCursorAfterHID: restoreCursorAfterHID,
            showMenuBarIcon: showMenuBarIcon
        )
        do {
            try settingsStore.save(settings)
        } catch {
            InjectLogger.log(.target, "settings save failed: \(error.localizedDescription)")
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

public extension Notification.Name {
    static let showClickOverlay = Notification.Name("showClickOverlay")
    static let hideClickOverlay = Notification.Name("hideClickOverlay")
    static let keymapEditorDidFinish = Notification.Name("keymapEditorDidFinish")
}
