import AppKit
import Combine
import InputRuntime

@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private weak var runtime: InputRuntime?
    private var statusItem: NSStatusItem?
    private var cancellables = Set<AnyCancellable>()
    var onOpenSettings: (() -> Void)?

    func attach(runtime: InputRuntime) {
        self.runtime = runtime
        cancellables.removeAll()
        runtime.$showMenuBarIcon
            .receive(on: RunLoop.main)
            .sink { [weak self] show in
                self?.applyMenuBarVisibility(show)
            }
            .store(in: &cancellables)
        applyMenuBarVisibility(runtime.showMenuBarIcon)
    }

    /// Only manages the status item. Dock / activation policy is owned by AppDelegate
    /// so Settings open/close can show Dock without fighting this controller.
    func applyMenuBarVisibility(_ show: Bool) {
        if show {
            createStatusItemIfNeeded()
        } else {
            removeStatusItem()
        }
    }

    private func createStatusItemIfNeeded() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "hammer.fill", accessibilityDescription: "Striker")
        }
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    private func removeStatusItem() {
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        statusItem = nil
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let runtime else { return }

        let toggle = NSMenuItem(
            title: String(localized: "menu.enable"),
            action: #selector(toggleEnabled),
            keyEquivalent: ""
        )
        toggle.target = self
        toggle.state = runtime.isEnabled ? .on : .off
        menu.addItem(toggle)

        let schemeRoot = NSMenuItem(
            title: String(localized: "menu.scheme"),
            action: nil,
            keyEquivalent: ""
        )
        let schemeMenu = NSMenu()
        if runtime.schemes.isEmpty {
            let empty = NSMenuItem(
                title: String(localized: "menu.noSchemes"),
                action: nil,
                keyEquivalent: ""
            )
            empty.isEnabled = false
            schemeMenu.addItem(empty)
            schemeRoot.isEnabled = false
        } else {
            for scheme in runtime.schemes {
                let item = NSMenuItem(
                    title: scheme.name,
                    action: #selector(selectScheme(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = scheme.id
                item.state = (scheme.id == runtime.activeSchemeID) ? .on : .off
                schemeMenu.addItem(item)
            }
        }
        schemeRoot.submenu = schemeMenu
        menu.addItem(schemeRoot)

        menu.addItem(NSMenuItem.separator())

        let settings = NSMenuItem(
            title: String(localized: "menu.settings"),
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settings.target = self
        menu.addItem(settings)

        menu.addItem(NSMenuItem.separator())

        let quit = NSMenuItem(
            title: String(localized: "menu.quit"),
            action: #selector(NSApplication.shared.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quit)
    }

    @objc private func toggleEnabled() {
        runtime?.isEnabled.toggle()
    }

    @objc private func selectScheme(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        runtime?.selectScheme(id: id)
    }

    @objc private func openSettings() {
        onOpenSettings?()
    }
}
