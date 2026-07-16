import AppKit
import SwiftUI
import InputRuntime

/// Native Safari / Calendar–style preference tabs via `NSTabViewController.tabStyle = .toolbar`.
/// Icons live in the window toolbar (`.preference` style) and do not move when pane height changes.
@MainActor
final class SettingsTabViewController: NSTabViewController {
    static let contentWidth: CGFloat = 460

    private let runtime: InputRuntime

    enum Pane: Int, CaseIterable {
        case general
        case keymap
        case compatibility
        case about

        /// Content area height only (toolbar tabs sit outside this).
        /// Sized so each pane fits without scrolling — Apple preference-window guidance.
        var contentHeight: CGFloat {
            switch self {
            case .general: return 380
            case .keymap: return 280
            case .compatibility: return 640
            case .about: return 140
            }
        }

        var label: String {
            switch self {
            case .general: String(localized: "tab.general")
            case .keymap: String(localized: "tab.keymap")
            case .compatibility: String(localized: "tab.compatibility")
            case .about: String(localized: "tab.about")
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

    init(runtime: InputRuntime) {
        self.runtime = runtime
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        tabStyle = .toolbar
        // Cross-fade pane content; toolbar icons stay put (native preference behavior).
        transitionOptions = [.crossfade]

        for pane in Pane.allCases {
            let hosting = makeHostingController(for: pane)
            hosting.view.frame = NSRect(
                x: 0,
                y: 0,
                width: Self.contentWidth,
                height: pane.contentHeight
            )
            let item = NSTabViewItem(viewController: hosting)
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
        resizeWindow(for: selectedPane, animated: true)
    }

    private var selectedPane: Pane {
        Pane(rawValue: selectedTabViewItemIndex) ?? .general
    }

    private func makeHostingController(for pane: Pane) -> NSHostingController<AnyView> {
        let root: AnyView
        switch pane {
        case .general:
            root = AnyView(GeneralSettingsView().environmentObject(runtime))
        case .keymap:
            root = AnyView(KeymapSettingsView().environmentObject(runtime))
        case .compatibility:
            root = AnyView(CompatibilitySettingsView().environmentObject(runtime))
        case .about:
            root = AnyView(AboutSettingsView())
        }
        return NSHostingController(rootView: root)
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

        if animated {
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
}
