import Cocoa
import Combine
import SwiftUI
import InputRuntime
import EditorKit

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private(set) var runtime: InputRuntime?
    private let statusItemController = StatusItemController()
    private let keymapHUD = KeymapHUDController()
    private var settingsWindow: NSWindow?
    private var overlayWindow: NSWindow?
    private var isSettingsVisible = false
    private var cancellables = Set<AnyCancellable>()

    private static let settingsWidth: CGFloat = SettingsTabViewController.contentWidth

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Clear any leftover in-app AppleLanguages override from earlier builds so
        // System Settings → Language & Region → Applications remains authoritative.
        UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let runtime = InputRuntime()
        self.runtime = runtime

        statusItemController.onOpenSettings = { [weak self] in
            self?.openSettings()
        }
        statusItemController.attach(runtime: runtime)

        runtime.$showMenuBarIcon
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshActivationPolicy()
            }
            .store(in: &cancellables)

        runtime.startIfNeeded()
        bindKeymapHUD(runtime)
        refreshActivationPolicy()

        setupOverlayWindow()
        NotificationCenter.default.addObserver(self, selector: #selector(handleShowClickOverlay), name: .showClickOverlay, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleHideClickOverlay), name: .hideClickOverlay, object: nil)
    }

    @objc func openSettings() {
        guard let runtime else { return }

        if settingsWindow == nil {
            let tabs = SettingsTabViewController(runtime: runtime)
            let initialHeight = SettingsTabViewController.Pane.general.contentHeight

            // Preference window: titled + closable. Width fixed; height follows selected pane.
            // Use a panel subclass that ignores Esc — system Settings / Safari prefs do not
            // dismiss on Escape (that behavior is for sheets and modal alerts).
            let window = PreferencePanel(
                contentRect: NSRect(x: 0, y: 0, width: Self.settingsWidth, height: initialHeight),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = String(localized: "settings.window.title")
            // `.toolbar` tab style auto-adopts `.preference` toolbar (Safari / Calendar Settings).
            window.contentViewController = tabs
            window.isReleasedWhenClosed = false
            window.hidesOnDeactivate = false
            window.delegate = self
            window.center()
            settingsWindow = window
        }

        isSettingsVisible = true
        refreshActivationPolicy()
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    private func bindKeymapHUD(_ runtime: InputRuntime) {
        runtime.$keymap
            .combineLatest(runtime.$keymapButtonShape)
            .sink { [weak self] keymap, shape in
                self?.keymapHUD.updateAppearance(keymap: keymap, buttonShape: shape)
            }
            .store(in: &cancellables)

        runtime.$showKeymapOverlay
            .combineLatest(runtime.$isEditing, runtime.$targetBundleID)
            .sink { [weak self] show, editing, bundleID in
                if show, !editing, let bundleID {
                    self?.keymapHUD.start(targetBundleID: bundleID)
                } else {
                    self?.keymapHUD.stop()
                }
            }
            .store(in: &cancellables)
    }

    /// Dock while Settings is open (or menu-bar icon is hidden); otherwise menu-bar agent.
    private func refreshActivationPolicy() {
        let showMenuBarIcon = runtime?.showMenuBarIcon ?? true
        let showDock = isSettingsVisible || !showMenuBarIcon
        NSApp.setActivationPolicy(showDock ? .regular : .accessory)
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        guard notification.object as? NSWindow === settingsWindow else { return }
        isSettingsVisible = false
        refreshActivationPolicy()
    }

    // MARK: - Click overlay

    func setupOverlayWindow() {
        overlayWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 50, height: 50),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        overlayWindow?.isOpaque = false
        overlayWindow?.backgroundColor = .clear
        overlayWindow?.level = .floating
        overlayWindow?.ignoresMouseEvents = true
        overlayWindow?.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        overlayWindow?.contentView = NSHostingView(rootView: ClickOverlayView())
    }

    @objc func handleShowClickOverlay(notification: Notification) {
        if let clickPoint = notification.object as? CGPoint {
            showOverlay(at: clickPoint)
        }
    }

    @objc func handleHideClickOverlay(notification: Notification) {
        hideOverlay()
    }

    func showOverlay(at point: CGPoint) {
        guard let overlayWindow else { return }
        let windowSize = overlayWindow.frame.size
        overlayWindow.setFrameOrigin(NSPoint(
            x: point.x - windowSize.width / 2,
            y: point.y - windowSize.height / 2
        ))
        overlayWindow.orderFront(nil)
    }

    func hideOverlay() {
        overlayWindow?.orderOut(nil)
    }
}

/// Preference window that does not close when the user presses Escape.
private final class PreferencePanel: NSPanel {
    override func cancelOperation(_ sender: Any?) {
        // Intentionally empty. Default NSPanel dismisses on Esc; preference windows do not.
    }
}
