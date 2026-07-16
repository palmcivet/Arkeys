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
    @Published public var capability: CapabilityReport?
    @Published public var lastInjectSummary: String = ""
    @Published public var lastInjectPosted: Bool?

    public var onEditorKeyDown: ((UInt16, String) -> Void)?

    private var globalKeyMonitor: Any?
    private var localKeyMonitor: Any?
    private let injector = EventInjector()
    private let store = KeymapStore()
    private let settingsStore = AppSettingsStore()
    private var didStart = false
    private var isRestoringSettings = false
    private var pendingInjectModeRaw: String?
    /// Last non-Arkeys app that was frontmost — used by Compatibility Test Click.
    private var previousFrontmostApp: NSRunningApplication?
    private var frontmostObserver: NSObjectProtocol?

    public init() {
        DispatchQueue.main.async { [weak self] in
            self?.startIfNeeded()
        }
    }

    deinit {
        if let frontmostObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(frontmostObserver)
        }
        // Monitors removed best-effort; NSEvent APIs are main-thread.
    }

    public func startIfNeeded() {
        guard !didStart else { return }
        didStart = true
        restoreSettings()
        applyCapability(CapabilityProbe.run(promptAccessibility: true))
        startMonitoring()
        startTrackingFrontmost()
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
            // While editing, swallow Escape so AppKit doesn't also treat it as cancel /
            // so we don't bind Escape as a hotkey and then dismiss in the same press.
            // 53 == Carbon kVK_Escape (same as KeymapEditorController.escapeKeyCode).
            if event.keyCode == 53, self?.isEditing == true {
                return nil
            }
            return event
        }

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
    }

    /// Bind a specific running app as the injection target (focus gate).
    public func bind(app: NSRunningApplication) {
        guard let bundleID = app.bundleIdentifier else {
            InjectLogger.log(.target, "cannot bind — missing bundle id")
            return
        }
        if bundleID == Bundle.main.bundleIdentifier {
            InjectLogger.log(.target, "skip binding Arkeys itself")
            return
        }
        bind(bundleID: bundleID, appName: app.localizedName ?? bundleID)
    }

    public func bind(bundleID: String, appName: String? = nil) {
        if bundleID == Bundle.main.bundleIdentifier {
            InjectLogger.log(.target, "skip binding Arkeys itself")
            return
        }
        targetBundleID = bundleID
        targetAppName = appName ?? RunningAppCatalog.runningApplication(bundleID: bundleID)?.localizedName ?? bundleID
        reloadSchemesFromStore()
        persistSettings()
        InjectLogger.log(.target, "bound target=\(targetAppName) id=\(bundleID)")
    }

    /// Create a blank Arkeys keymap scheme for the current target and persist it.
    @discardableResult
    public func createNewKeymap(name: String = "Untitled") -> Bool {
        guard let targetBundleID else {
            InjectLogger.log(.target, "cannot create keymap — no target")
            return false
        }
        let blank = CanonicalKeymap(targetHint: targetBundleID, source: .arkeys(version: "1.0.0"))
        do {
            let meta = try store.create(keymap: blank, bundleID: targetBundleID, name: name)
            activeSchemeID = meta.id
            keymap = blank
            refreshSchemesList()
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
            persistSettings()
        } catch {
            InjectLogger.log(.target, "import save failed: \(error.localizedDescription)")
        }
    }

    /// Delete the currently active scheme (or clear state if none remain).
    public func deleteActiveScheme() {
        guard let targetBundleID else { return }
        guard let activeSchemeID else {
            keymap = CanonicalKeymap(targetHint: targetBundleID, source: .arkeys(version: "1.0.0"))
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

    public func refreshCapability() {
        applyCapability(CapabilityProbe.run(promptAccessibility: false))
        if globalKeyMonitor == nil {
            startMonitoring()
        }
    }

    public func fireClick(relativeX: Double, relativeY: Double) {
        guard let target = TargetResolver.resolveFrontmost(relativeX: relativeX, relativeY: relativeY) else {
            lastInjectSummary = "app=? resolve failed"
            lastInjectPosted = false
            return
        }
        performClick(on: target)
    }

    /// Compatibility Test Click: inject into the previous (non-Arkeys) frontmost window.
    /// Settings is frontmost when the button is pressed, so `resolveFrontmost` would hit Arkeys.
    public func fireTestClick(relativeX: Double, relativeY: Double) {
        let app = usablePreviousFrontmost() ?? frontmostExcludingSelf()
        guard let app else {
            lastInjectSummary = "app=? resolve failed (no previous window)"
            lastInjectPosted = false
            return
        }
        let appName = app.localizedName ?? app.bundleIdentifier ?? "?"
        guard let target = TargetResolver.resolve(app: app, relativeX: relativeX, relativeY: relativeY) else {
            lastInjectSummary = "app=\(appName) resolve failed (no window)"
            lastInjectPosted = false
            return
        }
        performClick(on: target)
    }

    /// Prompt TCC (system Accessibility Access dialog when eligible), then open the
    /// Accessibility privacy pane so the user can toggle Arkeys if they already denied.
    public func openAccessibilitySettings() {
        applyCapability(CapabilityProbe.run(promptAccessibility: true))
        openAccessibilityPrivacyPane()
        if globalKeyMonitor == nil {
            startMonitoring()
        }
    }

    private func openAccessibilityPrivacyPane() {
        let candidates = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
        ]
        for candidate in candidates {
            if let url = URL(string: candidate), NSWorkspace.shared.open(url) {
                return
            }
        }
    }

    private func performClick(on target: InjectionTarget) {
        syncInjectorOptions()
        NotificationCenter.default.post(name: .showClickOverlay, object: target.clickPointAppKit)
        let result = injector.injectClick(mode: injectMode, target: target)
        lastInjectSummary = "app=\(target.appName) \(result.summary)"
        lastInjectPosted = result.posted
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            NotificationCenter.default.post(name: .hideClickOverlay, object: nil)
        }
    }

    private func startTrackingFrontmost() {
        rememberFrontmostIfExternal(NSWorkspace.shared.frontmostApplication)
        frontmostObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            Task { @MainActor in
                self?.rememberFrontmostIfExternal(app)
            }
        }
    }

    private func rememberFrontmostIfExternal(_ app: NSRunningApplication?) {
        guard let app, !isSelf(app) else { return }
        previousFrontmostApp = app
    }

    private func usablePreviousFrontmost() -> NSRunningApplication? {
        guard let app = previousFrontmostApp, !app.isTerminated else {
            previousFrontmostApp = nil
            return nil
        }
        return app
    }

    private func frontmostExcludingSelf() -> NSRunningApplication? {
        guard let front = NSWorkspace.shared.frontmostApplication, !isSelf(front) else {
            return nil
        }
        return front
    }

    private func isSelf(_ app: NSRunningApplication) -> Bool {
        app.bundleIdentifier == Bundle.main.bundleIdentifier
    }

    private func applyCapability(_ report: CapabilityReport) {
        capability = report
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

        guard isEnabled else {
            InjectLogger.log(.inject, "skip: disabled")
            return
        }
        guard let targetBundleID else {
            InjectLogger.log(.inject, "skip: no target bound")
            return
        }
        guard let front = NSWorkspace.shared.frontmostApplication else {
            InjectLogger.log(.inject, "skip: no frontmost app")
            return
        }
        guard front.bundleIdentifier == targetBundleID else {
            InjectLogger.log(.inject, "skip: frontmost=\(front.bundleIdentifier ?? "nil") target=\(targetBundleID)")
            return
        }

        let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard mods.isEmpty else {
            InjectLogger.log(.inject, "skip: modifier held \(mods.rawValue)")
            return
        }

        guard let button = keymap.button(matchingKeyCode: keyCode) else {
            InjectLogger.log(.inject, "skip: no binding for keyCode=\(keyCode) (bindings=\(keymap.runnableButtons.count))")
            return
        }
        InjectLogger.log(.inject, "matched binding \(button.key.name) @ (\(button.transform.x),\(button.transform.y))")
        fireClick(relativeX: button.transform.x, relativeY: button.transform.y)
    }

    private func syncInjectorOptions() {
        injector.preferMouseMovedBeforeHID = preferMouseMovedBeforeHID
        injector.restoreCursorAfterHID = restoreCursorAfterHID
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
            return
        }
        refreshSchemesList()
        if let active = store.loadActive(bundleID: targetBundleID) {
            activeSchemeID = active.meta.id
            keymap = active.keymap
        } else {
            activeSchemeID = nil
            keymap = CanonicalKeymap(targetHint: targetBundleID, source: .arkeys(version: "1.0.0"))
        }
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
