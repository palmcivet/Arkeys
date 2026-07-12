import Cocoa
import SwiftUI
import InputRuntime

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private(set) var runtime: InputRuntime?
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var overlayWindow: NSWindow?

    private static let settingsWidth: CGFloat = 460

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Hide Dock icon before the app finishes launching.
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let runtime = InputRuntime()
        self.runtime = runtime

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "hammer.fill", accessibilityDescription: "Striker")
        }
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item

        runtime.startIfNeeded()

        setupOverlayWindow()
        NotificationCenter.default.addObserver(self, selector: #selector(handleShowClickOverlay), name: .showClickOverlay, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleHideClickOverlay), name: .hideClickOverlay, object: nil)
    }

    // MARK: - Tray menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let enabled = runtime?.isEnabled ?? false
        let toggle = NSMenuItem(
            title: "启用",
            action: #selector(toggleEnabled),
            keyEquivalent: ""
        )
        toggle.state = enabled ? .on : .off
        menu.addItem(toggle)

        menu.addItem(NSMenuItem(title: "设置", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(NSApplication.shared.terminate(_:)), keyEquivalent: "q"))
    }

    @objc func toggleEnabled() {
        runtime?.isEnabled.toggle()
    }

    @objc func openSettings() {
        guard let runtime else { return }

        if settingsWindow == nil {
            let root = ContentView().environmentObject(runtime)
            let hosting = NSHostingController(rootView: root)
            hosting.view.frame.size = NSSize(width: Self.settingsWidth, height: 560)

            let window = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: Self.settingsWidth, height: 560),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Striker 设置"
            window.contentViewController = hosting
            window.isReleasedWhenClosed = false
            window.hidesOnDeactivate = false
            // Fixed width; height remains resizable.
            window.contentMinSize = NSSize(width: Self.settingsWidth, height: 400)
            window.contentMaxSize = NSSize(width: Self.settingsWidth, height: 10_000)
            window.center()
            settingsWindow = window
        }

        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
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
