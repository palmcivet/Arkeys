import Cocoa
import SwiftUI
import InputRuntime

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var overlayWindow: NSWindow?
    private weak var runtime: InputRuntime?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "hammer.fill", accessibilityDescription: "Striker")
            button.action = #selector(statusItemClicked(_:))
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        statusItem = item

        let pop = NSPopover()
        pop.contentSize = NSSize(width: 460, height: 560)
        pop.behavior = .transient
        popover = pop

        if let runtime {
            installPopoverContent(runtime: runtime)
        }

        setupOverlayWindow()
        NotificationCenter.default.addObserver(self, selector: #selector(handleShowClickOverlay), name: .showClickOverlay, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleHideClickOverlay), name: .hideClickOverlay, object: nil)
    }

    func bind(runtime: InputRuntime) {
        self.runtime = runtime
        Task { @MainActor in
            runtime.startIfNeeded()
        }
        installPopoverContent(runtime: runtime)
    }

    private func installPopoverContent(runtime: InputRuntime) {
        guard let popover else { return }
        let root = ContentView().environmentObject(runtime)
        popover.contentViewController = NSHostingController(rootView: root)
    }

    @objc func statusItemClicked(_ sender: AnyObject?) {
        guard let event = NSApp.currentEvent else {
            openSettings()
            return
        }
        if event.type == .rightMouseUp {
            guard let statusItem else { return }
            let menu = createMenu()
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            DispatchQueue.main.async {
                statusItem.menu = nil
            }
            return
        }
        openSettings()
    }

    func createMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "设置", action: #selector(openSettings), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "绑定前台为目标", action: #selector(bindFrontmost), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(NSApplication.shared.terminate(_:)), keyEquivalent: "q"))
        return menu
    }

    @objc func bindFrontmost() {
        Task { @MainActor in
            runtime?.bindFrontmostApp()
        }
    }

    @objc func openSettings() {
        guard let statusItem, let button = statusItem.button else { return }

        if popover == nil {
            let pop = NSPopover()
            pop.contentSize = NSSize(width: 460, height: 560)
            pop.behavior = .transient
            popover = pop
        }
        guard let popover else { return }

        if let runtime {
            installPopoverContent(runtime: runtime)
        }

        if popover.isShown {
            popover.performClose(nil)
            return
        }

        guard popover.contentViewController != nil else { return }

        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

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
