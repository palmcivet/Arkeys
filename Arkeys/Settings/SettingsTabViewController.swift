import AppKit
import SwiftUI
import InputRuntime

/// Native Safari / Calendar–style preference tabs via `NSTabViewController.tabStyle = .toolbar`.
/// Icons live in the window toolbar (`.preference` style) and do not move when pane height changes.
@MainActor
final class SettingsTabViewController: NSTabViewController {
    static let contentWidth: CGFloat = 460

    private let runtime: InputRuntime
    private let editorSession: EditorSession
    private var motionObserver: NSObjectProtocol?

    enum Pane: Int, CaseIterable {
        case general
        case keymap
        case compatibility
        case about

        /// Content area height only (toolbar tabs sit outside this).
        /// Sized so each pane fits without scrolling — Apple preference-window guidance.
        var contentHeight: CGFloat {
            switch self {
            case .general: return 440
            case .keymap: return 530
            case .compatibility: return 630
            case .about: return 140
            }
        }

        var label: String {
            switch self {
            case .general: String(localized: "settings.tab.general")
            case .keymap: String(localized: "settings.tab.keymap")
            case .compatibility: String(localized: "settings.tab.compatibility")
            case .about: String(localized: "settings.tab.about")
            }
        }

        var systemImage: String {
            switch self {
            case .general: "gearshape"
            case .keymap: "keyboard"
            case .compatibility: "checkmark.shield"
            case .about: "info.circle"
            }
        }
    }

    init(runtime: InputRuntime, editorSession: EditorSession) {
        self.runtime = runtime
        self.editorSession = editorSession
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let motionObserver {
            NotificationCenter.default.removeObserver(motionObserver)
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        tabStyle = .toolbar
        applyMotionPreference()
        if motionObserver == nil {
            motionObserver = NotificationCenter.default.addObserver(
                forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.applyMotionPreference()
                }
            }
        }

        for pane in Pane.allCases {
            let controller = makeViewController(for: pane)
            controller.view.frame = NSRect(
                x: 0,
                y: 0,
                width: Self.contentWidth,
                height: pane.contentHeight
            )
            let item = NSTabViewItem(viewController: controller)
            item.label = pane.label
            item.image = NSImage(systemSymbolName: pane.systemImage, accessibilityDescription: pane.label)
            addTabViewItem(item)
        }
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        resizeWindow(for: selectedPane, animated: false)
    }

    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        let pane = selectedPane
        // Wait until NSTabView finishes the toolbar transition. Resizing in-line
        // fights `NSHostingController` ideal-size and can abort the layout pass.
        DispatchQueue.main.async { [weak self] in
            self?.resizeWindow(for: pane, animated: true)
        }
    }

    private var selectedPane: Pane {
        Pane(rawValue: selectedTabViewItemIndex) ?? .general
    }

    private func makeViewController(for pane: Pane) -> NSViewController {
        let root: AnyView
        switch pane {
        case .general:
            root = AnyView(GeneralSettingsView().environmentObject(runtime))
        case .keymap:
            root = AnyView(KeymapSettingsView(session: editorSession).environmentObject(runtime))
        case .compatibility:
            root = AnyView(CompatibilitySettingsView().environmentObject(runtime))
        case .about:
            root = AnyView(AboutSettingsView())
        }
        let controller = NSHostingController(rootView: root)
        // Preference panes use a fixed window height. If the host publishes an
        // ideal size, AppKit fights the tab-switch resize and can crash.
        controller.sizingOptions = []
        controller.preferredContentSize = NSSize(width: Self.contentWidth, height: pane.contentHeight)
        return controller
    }

    /// Animate content height; preference toolbar icons remain fixed in the titlebar.
    private func resizeWindow(for pane: Pane, animated: Bool) {
        guard let window = view.window else { return }

        let contentRect = NSRect(x: 0, y: 0, width: Self.contentWidth, height: pane.contentHeight)
        let frameSize = window.frameRect(forContentRect: contentRect).size
        var newFrame = window.frame
        newFrame.origin.y += newFrame.size.height - frameSize.height
        newFrame.size = frameSize

        guard abs(window.frame.height - newFrame.height) > 0.5 else { return }

        if animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                context.allowsImplicitAnimation = true
                window.animator().setFrame(newFrame, display: true)
            }
        } else {
            window.setFrame(newFrame, display: true)
        }
    }

    private func applyMotionPreference() {
        transitionOptions = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            ? []
            : [.crossfade]
    }
}
