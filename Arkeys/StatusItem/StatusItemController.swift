import AppKit
import Combine
import InputRuntime

@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private weak var runtime: InputRuntime?
    private weak var editorSession: EditorSession?
    private var statusItem: NSStatusItem?
    private var cancellables = Set<AnyCancellable>()
    var onOpenSettings: (() -> Void)?

    func attach(runtime: InputRuntime, editorSession: EditorSession) {
        self.runtime = runtime
        self.editorSession = editorSession
        cancellables.removeAll()
        runtime.$showMenuBarIcon
            .combineLatest(runtime.$isEditing)
            .receive(on: RunLoop.main)
            .sink { [weak self] show, _ in
                self?.applyMenuBarVisibility(show)
            }
            .store(in: &cancellables)
        applyMenuBarVisibility(runtime.showMenuBarIcon)
    }

    /// Only manages the status item. Dock / activation policy is owned by AppDelegate
    /// so Settings open/close can show Dock without fighting this controller.
    /// Editing always shows the icon so Done / Cancel stay reachable.
    func applyMenuBarVisibility(_ show: Bool) {
        let forceShow = runtime?.isEditing == true
        if show || forceShow {
            createStatusItemIfNeeded()
            updateTooltip()
        } else {
            removeStatusItem()
        }
    }

    private func createStatusItemIfNeeded() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = Self.menuBarImage()
            button.setAccessibilityLabel("Arkeys")
        }
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
        updateTooltip()
    }

    /// The asset is a vector template, so it is copied before resizing to avoid
    /// mutating the instance the asset catalog hands back.
    private static func menuBarImage() -> NSImage? {
        guard let image = NSImage(named: "MenuBarIcon")?.copy() as? NSImage else {
            return NSImage(systemSymbolName: "hammer.fill", accessibilityDescription: "Arkeys")
        }
        image.isTemplate = true
        image.size = NSSize(width: 18, height: 18)
        return image
    }

    private func removeStatusItem() {
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        statusItem = nil
    }

    private func updateTooltip() {
        guard let button = statusItem?.button else { return }
        if runtime?.isEditing == true {
            button.toolTip = String(localized: "menu.editing.tooltip")
        } else {
            button.toolTip = "Arkeys"
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        editorSession?.controller.isStatusMenuTracking = true
        menu.removeAllItems()
        guard let runtime else { return }
        let editing = runtime.isEditing

        let toggle = NSMenuItem(
            title: String(localized: "menu.enable"),
            action: #selector(toggleEnabled),
            keyEquivalent: ""
        )
        toggle.target = self
        toggle.state = runtime.isEnabled ? .on : .off
        toggle.isEnabled = !editing
        menu.addItem(toggle)

        let overlay = NSMenuItem(
            title: String(localized: "menu.showOverlay"),
            action: #selector(toggleShowOverlay),
            keyEquivalent: ""
        )
        overlay.target = self
        overlay.state = runtime.showKeymapOverlay ? .on : .off
        overlay.isEnabled = !editing
        menu.addItem(overlay)

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
                item.isEnabled = !editing
                schemeMenu.addItem(item)
            }
            schemeRoot.isEnabled = !editing
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
        settings.isEnabled = !editing
        menu.addItem(settings)

        if editing {
            menu.addItem(NSMenuItem.separator())

            let done = NSMenuItem(
                title: String(localized: "menu.editor.done"),
                action: #selector(finishEditing),
                keyEquivalent: ""
            )
            done.target = self
            menu.addItem(done)

            let cancel = NSMenuItem(
                title: String(localized: "menu.editor.cancel"),
                action: #selector(cancelEditing),
                keyEquivalent: ""
            )
            cancel.target = self
            menu.addItem(cancel)
        }

        menu.addItem(NSMenuItem.separator())

        let quit = NSMenuItem(
            title: String(localized: "menu.quit"),
            action: #selector(NSApplication.shared.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quit)
    }

    func menuDidClose(_ menu: NSMenu) {
        editorSession?.controller.isStatusMenuTracking = false
    }

    @objc private func finishEditing() {
        editorSession?.finish()
    }

    @objc private func cancelEditing() {
        editorSession?.cancel()
    }

    @objc private func toggleEnabled() {
        runtime?.isEnabled.toggle()
    }

    @objc private func toggleShowOverlay() {
        runtime?.showKeymapOverlay.toggle()
    }

    @objc private func selectScheme(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        runtime?.selectScheme(id: id)
    }

    @objc private func openSettings() {
        onOpenSettings?()
    }
}
