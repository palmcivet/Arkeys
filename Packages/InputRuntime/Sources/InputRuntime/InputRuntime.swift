import Foundation
import AppKit
import Combine
import KeymapCore
import Injection
import Targeting

/// A target app that already has at least one saved keymap scheme.
public struct ConfiguredTarget: Identifiable, Hashable, Sendable {
    public var id: String { bundleID }
    public let bundleID: String
    public let appName: String
    public let schemes: [KeymapSchemeMeta]
    public let activeSchemeID: UUID?

    public init(bundleID: String, appName: String, schemes: [KeymapSchemeMeta], activeSchemeID: UUID?) {
        self.bundleID = bundleID
        self.appName = appName
        self.schemes = schemes
        self.activeSchemeID = activeSchemeID
    }
}

@MainActor
public final class InputRuntime: ObservableObject {
    @Published public var targetBundleID: String?
    @Published public var targetAppName: String?
    @Published public var keymap: CanonicalKeymap = CanonicalKeymap()
    @Published public var schemes: [KeymapSchemeMeta] = []
    @Published public var activeSchemeID: UUID?
    @Published public var configuredTargets: [ConfiguredTarget] = []
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
    @Published public var keymapButtonShape: KeymapButtonShape = .circle {
        didSet { persistSettings() }
    }
    @Published public var showKeymapOverlay: Bool = false {
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
    private var persistTask: Task<Void, Never>?
    /// Last non-Arkeys app that was frontmost — used by Compatibility Test Click.
    private var previousFrontmostApp: NSRunningApplication?
    private var frontmostObserver: NSObjectProtocol?
    private var activationObserver: NSObjectProtocol?
    private var accessibilityAPIObserver: NSObjectProtocol?
    /// Global monitors installed while untrusted stay silent after the user
    /// enables Accessibility. True only if the current global monitor was
    /// created under a trusted process.
    private var globalMonitorBoundWhileTrusted = false

    public init() {
        DispatchQueue.main.async { [weak self] in
            self?.startIfNeeded()
        }
    }

    deinit {
        if let frontmostObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(frontmostObserver)
        }
        if let activationObserver {
            NotificationCenter.default.removeObserver(activationObserver)
        }
        if let accessibilityAPIObserver {
            DistributedNotificationCenter.default().removeObserver(accessibilityAPIObserver)
        }
        // Monitors removed best-effort; NSEvent APIs are main-thread.
    }

    public func startIfNeeded() {
        guard !didStart else { return }
        didStart = true
        AppLog.log(.capability, "starting (pid=\(ProcessInfo.processInfo.processIdentifier))")
        restoreSettings()
        applyCapability(CapabilityProbe.run(promptAccessibility: true))
        startMonitoring()
        startTrackingFrontmost()
        startPermissionObservers()
        AppLog.log(.capability, "ready: mode=\(injectMode.rawValue) target=\(targetBundleID ?? "nil") "
            + "bindings=\(keymap.runnableButtons.count) globalMonitor=\(globalKeyMonitor != nil) "
            + "ax=\(globalMonitorBoundWhileTrusted)")
    }

    public func startMonitoring() {
        installLocalKeyMonitorIfNeeded()
        // Reuse the startup probe — do not ask tccd a second time.
        let trusted = capability?.accessibilityTrusted ?? CapabilityProbe.isAccessibilityTrusted()
        AppLog.log(.capability, "startMonitoring: AXIsProcessTrusted=\(trusted)")
        syncGlobalKeyMonitor(trusted: trusted, forceRebind: false)
    }

    public func stopMonitoring() {
        removeGlobalKeyMonitor()
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
            self.localKeyMonitor = nil
        }
    }

    /// Bind a specific running app as the injection target (focus gate).
    public func bind(app: NSRunningApplication) {
        guard let bundleID = app.bundleIdentifier else {
            AppLog.log(.target, "cannot bind — missing bundle id")
            return
        }
        if bundleID == Bundle.main.bundleIdentifier {
            AppLog.log(.target, "skip binding self")
            return
        }
        bind(bundleID: bundleID, appName: app.localizedName ?? bundleID)
    }

    public func bind(bundleID: String, appName: String? = nil) {
        if bundleID == Bundle.main.bundleIdentifier {
            AppLog.log(.target, "skip binding self")
            return
        }
        targetBundleID = bundleID
        targetAppName = appName ?? resolvedAppName(bundleID: bundleID, stored: nil)
        reloadSchemesFromStore()
        persistTargetDisplayName()
        persistSettingsNow()
        AppLog.log(.target, "bound target=\(targetAppName ?? bundleID) id=\(bundleID)")
    }

    /// Bind a target and activate one of its schemes in a single step.
    public func switchTo(bundleID: String, schemeID: UUID) {
        if targetBundleID != bundleID {
            bind(bundleID: bundleID)
        }
        selectScheme(id: schemeID)
    }

    /// Create a blank Arkeys keymap scheme for the current target and persist it.
    @discardableResult
    public func createNewKeymap(name: String = "Untitled") -> Bool {
        guard let targetBundleID else {
            AppLog.log(.target, "cannot create keymap — no target")
            return false
        }
        let blank = CanonicalKeymap(targetHint: targetBundleID, source: .arkeys(version: "1.0.0"))
        do {
            let meta = try store.create(keymap: blank, bundleID: targetBundleID, name: name)
            activeSchemeID = meta.id
            keymap = blank
            persistTargetDisplayName()
            refreshSchemesList()
            refreshConfiguredTargets()
            AppLog.log(.target, "created new empty keymap for \(targetBundleID)")
            return true
        } catch {
            AppLog.log(.target, "create failed: \(error.localizedDescription)")
            return false
        }
    }

    public func selectableApps() -> [SelectableApp] {
        RunningAppCatalog.selectableApps()
    }

    public func selectScheme(id: UUID) {
        guard let targetBundleID else { return }
        guard schemes.contains(where: { $0.id == id }) else { return }
        guard activeSchemeID != id else { return }
        do {
            try store.setActive(schemeID: id, bundleID: targetBundleID)
            activeSchemeID = id
            if let loaded = store.load(bundleID: targetBundleID, schemeID: id) {
                keymap = loaded
            }
            refreshConfiguredTargets()
            AppLog.log(.target, "selected scheme \(id.uuidString)")
        } catch {
            AppLog.log(.target, "select scheme failed: \(error.localizedDescription)")
        }
    }

    public func renameScheme(id: UUID, name: String) {
        guard let targetBundleID else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            try store.rename(schemeID: id, bundleID: targetBundleID, name: trimmed)
            refreshSchemesList()
            refreshConfiguredTargets()
        } catch {
            AppLog.log(.target, "rename failed: \(error.localizedDescription)")
        }
    }

    /// Copy the active scheme onto another target. Stays on the current target.
    @discardableResult
    public func copyActiveScheme(toBundleID: String, appName: String? = nil, name: String? = nil) -> Bool {
        guard let fromBundleID = targetBundleID, let schemeID = activeSchemeID else {
            AppLog.log(.target, "cannot copy — no active scheme")
            return false
        }
        if toBundleID == Bundle.main.bundleIdentifier {
            AppLog.log(.target, "skip copy onto self")
            return false
        }
        do {
            let sourceName = schemes.first { $0.id == schemeID }?.name
            let meta = try store.copyScheme(
                fromBundleID: fromBundleID,
                schemeID: schemeID,
                toBundleID: toBundleID,
                name: name ?? sourceName
            )
            if let appName, !appName.isEmpty {
                store.setDisplayName(appName, bundleID: toBundleID)
            }
            if toBundleID == fromBundleID {
                refreshSchemesList()
            }
            refreshConfiguredTargets()
            AppLog.log(.target, "copied scheme \(meta.id) to \(toBundleID)")
            return true
        } catch {
            AppLog.log(.target, "copy failed: \(error.localizedDescription)")
            return false
        }
    }

    public func saveKeymap() {
        guard let targetBundleID, let activeSchemeID else { return }
        do {
            try store.save(keymap, bundleID: targetBundleID, schemeID: activeSchemeID)
            refreshSchemesList()
            refreshConfiguredTargets()
            AppLog.log(.target, "saved keymap for \(targetBundleID) scheme=\(activeSchemeID)")
        } catch {
            AppLog.log(.target, "save failed: \(error.localizedDescription)")
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
            AppLog.log(.target, "import failed — no target")
            return
        }
        let name = suggestedName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? "Imported"
        do {
            let meta = try store.create(keymap: map, bundleID: targetBundleID, name: name)
            activeSchemeID = meta.id
            keymap = map
            persistTargetDisplayName()
            refreshSchemesList()
            refreshConfiguredTargets()
            persistSettingsNow()
        } catch {
            AppLog.log(.target, "import save failed: \(error.localizedDescription)")
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
            refreshConfiguredTargets()
            AppLog.log(.target, "deleted scheme \(activeSchemeID)")
        } catch {
            AppLog.log(.target, "delete failed: \(error.localizedDescription)")
        }
    }

    /// Remove every saved scheme for a target. If it is the current target,
    /// bind another remaining library or clear the selection.
    public func deleteTarget(bundleID: String) {
        do {
            try store.deleteTarget(bundleID: bundleID)
            AppLog.log(.target, "deleted target library \(bundleID)")
            refreshConfiguredTargets()
            if targetBundleID == bundleID {
                if let next = configuredTargets.first {
                    bind(bundleID: next.bundleID, appName: next.appName)
                } else {
                    clearTarget()
                }
            }
        } catch {
            AppLog.log(.target, "delete target failed: \(error.localizedDescription)")
        }
    }

    public func refreshCapability() {
        applyCapability(CapabilityProbe.run(promptAccessibility: false))
        syncGlobalKeyMonitor(trusted: capability?.accessibilityTrusted == true, forceRebind: true)
    }

    public func fireClick(relativeX: Double, relativeY: Double) {
        guard let target = TargetResolver.resolveFrontmost(relativeX: relativeX, relativeY: relativeY) else {
            AppLog.log(.inject, "fireClick: no frontmost window")
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

    /// Jump to System Settings → Accessibility. The grant dialog is first-launch
    /// only (`startIfNeeded`); observers rebind when the user toggles the row.
    public func openAccessibilitySettings() {
        openAccessibilityPrivacyPane()
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

    /// tccd lags `com.apple.accessibility.api`; retry instead of one sleep.
    /// The notification name is undocumented — activation is the fallback.
    private enum AccessibilityTCC {
        static let settle = Duration.milliseconds(150)
        static let attempts = 3
        static let apiDidChange = Notification.Name("com.apple.accessibility.api")
    }

    /// Local monitors work without Accessibility and should not be torn down
    /// just to rebind the global one.
    private func installLocalKeyMonitorIfNeeded() {
        guard localKeyMonitor == nil else { return }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let stroke = KeyStroke(event)
            var swallowEscape = false
            self.dispatchKeyStroke(stroke, source: "local") { editing in
                // Swallow Escape while editing so AppKit does not treat it as cancel.
                // Esc is a bindable key (e.g. game "back"), not an editor dismiss shortcut.
                swallowEscape = stroke.keyCode == CarbonKeyNames.escapeKeyCode && editing
            }
            return swallowEscape ? nil : event
        }
    }

    /// Bind or drop the global monitor so it matches TCC trust. Creating one
    /// while untrusted is worse than having none — it stays silent after grant.
    private func syncGlobalKeyMonitor(trusted: Bool, forceRebind: Bool) {
        if trusted && globalMonitorBoundWhileTrusted && !forceRebind { return }

        let hadGlobal = globalKeyMonitor != nil
        removeGlobalKeyMonitor()

        if trusted {
            installGlobalKeyMonitor()
        } else if hadGlobal {
            AppLog.log(.capability, "global key monitor removed — Accessibility not trusted")
        } else {
            AppLog.log(.capability, "skip global key monitor — Accessibility not trusted")
        }
    }

    private func installGlobalKeyMonitor() {
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.dispatchKeyStroke(KeyStroke(event), source: "global")
        }
        if globalKeyMonitor == nil {
            AppLog.log(.capability, "global key monitor FAILED — grant Accessibility access")
            globalMonitorBoundWhileTrusted = false
        } else {
            AppLog.log(.capability, "global key monitor started")
            globalMonitorBoundWhileTrusted = true
        }
    }

    private func removeGlobalKeyMonitor() {
        if let globalKeyMonitor {
            NSEvent.removeMonitor(globalKeyMonitor)
            self.globalKeyMonitor = nil
        }
        globalMonitorBoundWhileTrusted = false
    }

    /// Cheap AX read. Full `CapabilityProbe.run` (event tap + SkyLight) only
    /// when trust no longer matches the current global-monitor binding — grant
    /// and revoke both count.
    private func syncAccessibilityTrustIfChanged(settle: Bool) async {
        let trusted = await resolvedAccessibilityTrust(settle: settle)
        guard trusted != globalMonitorBoundWhileTrusted else { return }

        AppLog.log(.capability, "accessibility trust \(trusted ? "granted" : "revoked")")
        applyCapability(CapabilityProbe.run(promptAccessibility: false))
        syncGlobalKeyMonitor(
            trusted: capability?.accessibilityTrusted ?? trusted,
            forceRebind: false
        )
    }

    /// tccd's answer lags `com.apple.accessibility.api`. Retry only while we
    /// are still waiting to become trusted; revocation is typically immediate.
    private func resolvedAccessibilityTrust(settle: Bool) async -> Bool {
        var trusted = CapabilityProbe.isAccessibilityTrusted()
        guard settle, !trusted, !globalMonitorBoundWhileTrusted else {
            return trusted
        }
        for _ in 1..<AccessibilityTCC.attempts {
            try? await Task.sleep(for: AccessibilityTCC.settle)
            trusted = CapabilityProbe.isAccessibilityTrusted()
            if trusted { break }
        }
        return trusted
    }

    private func startPermissionObservers() {
        // Supported signal: user returns from System Settings.
        if activationObserver == nil {
            activationObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    await self?.syncAccessibilityTrustIfChanged(settle: false)
                }
            }
        }

        // Undocumented, but the usual signal when any Accessibility row changes.
        // Activation above is the fallback if this name goes away.
        if accessibilityAPIObserver == nil {
            accessibilityAPIObserver = DistributedNotificationCenter.default().addObserver(
                forName: AccessibilityTCC.apiDidChange,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    await self?.syncAccessibilityTrustIfChanged(settle: true)
                }
            }
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

    private var isTargetFrontmost: Bool {
        guard let targetBundleID,
              let target = RunningAppCatalog.runningApplication(bundleID: targetBundleID),
              let front = NSWorkspace.shared.frontmostApplication else {
            return false
        }
        return front.processIdentifier == target.processIdentifier
    }

    private func applyCapability(_ report: CapabilityReport) {
        if capability != report {
            capability = report
        }
        let raw = pendingInjectModeRaw ?? injectMode.rawValue
        let resolved = InjectMode.resolvedProductMode(raw: raw, report: report)
        pendingInjectModeRaw = nil
        if injectMode != resolved {
            injectMode = resolved
        }
    }

    /// Copy key data off `NSEvent` so monitor callbacks never hop a non-Sendable object.
    private struct KeyStroke: Sendable {
        let keyCode: UInt16
        let isARepeat: Bool
        let characters: String
        let modifierFlags: UInt

        init(_ event: NSEvent) {
            keyCode = event.keyCode
            isARepeat = event.isARepeat
            characters = event.charactersIgnoringModifiers ?? ""
            modifierFlags = event.modifierFlags.rawValue
        }
    }

    /// NSEvent monitors are installed on the main thread; stay there without an extra `Task`.
    nonisolated private func dispatchKeyStroke(
        _ stroke: KeyStroke,
        source: String,
        afterHandle: (@MainActor (Bool) -> Void)? = nil
    ) {
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                self.handleKeyStroke(stroke, source: source)
                afterHandle?(self.isEditing)
            }
        } else {
            Task { @MainActor in
                self.handleKeyStroke(stroke, source: source)
            }
        }
    }

    private func handleKeyStroke(_ stroke: KeyStroke, source: String) {
        if stroke.isARepeat { return }

        let keyCode = stroke.keyCode

        if isEditing {
            if isTargetFrontmost {
                let name = CarbonKeyNames.name(for: keyCode)
                onEditorKeyDown?(keyCode, name)
            }
            return
        }

        guard isEnabled else { return }
        guard let targetBundleID else { return }
        guard let front = NSWorkspace.shared.frontmostApplication,
              front.bundleIdentifier == targetBundleID else { return }

        // Only log key events when target app is frontmost (avoids flooding).
        AppLog.log(.inject, "keyDown source=\(source) keyCode=\(keyCode) chars=\(stroke.characters.debugDescription)")

        let mods = NSEvent.ModifierFlags(rawValue: stroke.modifierFlags)
            .intersection([.command, .option, .control, .shift])
        guard mods.isEmpty else {
            AppLog.log(.inject, "skip: modifier held \(mods.rawValue)")
            return
        }

        guard let button = keymap.button(matchingKeyCode: keyCode) else {
            AppLog.log(.inject, "skip: no binding for keyCode=\(keyCode) (bindings=\(keymap.runnableButtons.count))")
            return
        }
        AppLog.log(.inject, "matched \(button.key.name) @ (\(String(format: "%.3f,%.3f", button.transform.x, button.transform.y))) mode=\(injectMode.rawValue)")
        fireClick(relativeX: button.transform.x, relativeY: button.transform.y)
    }

    private func syncInjectorOptions() {
        injector.preferMouseMovedBeforeHID = preferMouseMovedBeforeHID
        injector.restoreCursorAfterHID = restoreCursorAfterHID
    }

    private func persistTargetDisplayName() {
        guard let targetBundleID, let name = targetAppName, !name.isEmpty else { return }
        store.setDisplayName(name, bundleID: targetBundleID)
    }

    private func resolvedAppName(bundleID: String, stored: String?) -> String {
        if let running = RunningAppCatalog.runningApplication(bundleID: bundleID)?.localizedName,
           !running.isEmpty {
            return running
        }
        if let stored, !stored.isEmpty {
            return stored
        }
        if bundleID == targetBundleID, let name = targetAppName, !name.isEmpty {
            return name
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return FileManager.default.displayName(atPath: url.path)
        }
        return bundleID
    }

    private func makeConfiguredTargets() -> [ConfiguredTarget] {
        store.listAllTargets().map { entry in
            ConfiguredTarget(
                bundleID: entry.bundleID,
                appName: resolvedAppName(bundleID: entry.bundleID, stored: entry.manifest.displayName),
                schemes: entry.manifest.schemes,
                activeSchemeID: entry.manifest.activeMeta?.id
            )
        }
        .sorted { $0.appName.localizedCaseInsensitiveCompare($1.appName) == .orderedAscending }
    }

    private func refreshSchemesList() {
        reloadCurrentSchemeState()
    }

    private func refreshConfiguredTargets() {
        configuredTargets = makeConfiguredTargets()
    }

    private func reloadCurrentSchemeState() {
        if let targetBundleID {
            let manifest = store.loadManifest(bundleID: targetBundleID)
            schemes = manifest.schemes
            activeSchemeID = manifest.activeMeta?.id
        } else {
            schemes = []
            activeSchemeID = nil
        }
    }

    private func clearTarget() {
        targetBundleID = nil
        targetAppName = nil
        schemes = []
        activeSchemeID = nil
        keymap = CanonicalKeymap()
        persistSettingsNow()
        AppLog.log(.target, "cleared target")
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
        refreshConfiguredTargets()
    }

    private func restoreSettings() {
        isRestoringSettings = true
        defer { isRestoringSettings = false }
        let settings = settingsStore.load()
        isEnabled = settings.isEnabled
        preferMouseMovedBeforeHID = settings.preferMouseMovedBeforeHID
        restoreCursorAfterHID = settings.restoreCursorAfterHID
        showMenuBarIcon = settings.showMenuBarIcon
        keymapButtonShape = settings.keymapButtonShape
        showKeymapOverlay = settings.showKeymapOverlay
        pendingInjectModeRaw = settings.injectModeRaw
        injectMode = InjectMode.resolvedProductMode(raw: settings.injectModeRaw, report: nil)
        AppLog.log(.capability, "settings: mode=\(injectMode.rawValue) "
            + "target=\(settings.lastTargetBundleID ?? "nil") enabled=\(isEnabled)")
        if let bundleID = settings.lastTargetBundleID {
            bind(bundleID: bundleID, appName: settings.lastTargetAppName)
        }
        refreshConfiguredTargets()
    }

    /// Coalesce rapid toggle writes; call `flushSettings()` on quit / window close.
    private func persistSettings() {
        guard !isRestoringSettings else { return }
        persistTask?.cancel()
        persistTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            self?.writeSettings()
        }
    }

    private func persistSettingsNow() {
        persistTask?.cancel()
        persistTask = nil
        writeSettings()
    }

    public func flushSettings() {
        persistSettingsNow()
    }

    private func writeSettings() {
        guard !isRestoringSettings else { return }
        let settings = AppSettings(
            lastTargetBundleID: targetBundleID,
            lastTargetAppName: targetAppName,
            isEnabled: isEnabled,
            injectModeRaw: injectMode.rawValue,
            preferMouseMovedBeforeHID: preferMouseMovedBeforeHID,
            restoreCursorAfterHID: restoreCursorAfterHID,
            showMenuBarIcon: showMenuBarIcon,
            keymapButtonShape: keymapButtonShape,
            showKeymapOverlay: showKeymapOverlay
        )
        do {
            try settingsStore.save(settings)
        } catch {
            AppLog.log(.target, "settings save failed: \(error.localizedDescription)")
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
