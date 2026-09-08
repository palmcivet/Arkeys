import Foundation
import AppKit
import SwiftUI
import Combine
import KeymapCore
import Targeting

private struct DragPreview: Equatable {
    var id: UUID
    var x: Double
    var y: Double
}

@MainActor
public final class KeymapEditorController: ObservableObject {
    @Published public var keymap: CanonicalKeymap
    @Published public var selectedID: UUID?
    @Published public var isActive: Bool = false
    @Published public var buttonShape: KeymapButtonShape = .circle
    @Published public var statusText: String = "Click empty area to add a button · drag to move · press a key to bind"
    @Published private var dragPreview: DragPreview?

    private var overlayWindow: NSWindow?
    private var followTimer: Timer?
    private var activationObserver: NSObjectProtocol?
    private var appActiveObserver: NSObjectProtocol?
    private var targetBundleID: String?
    private var lastOverlayFrame: CGRect?
    private var isOverlayPresented = false
    public var onFinished: ((CanonicalKeymap) -> Void)?
    public var onCancelled: (() -> Void)?

    public init(keymap: CanonicalKeymap = CanonicalKeymap()) {
        self.keymap = keymap
    }

    public func start(targetBundleID: String, keymap: CanonicalKeymap) {
        self.targetBundleID = targetBundleID
        self.keymap = keymap
        self.selectedID = nil
        self.dragPreview = nil
        self.lastOverlayFrame = nil
        self.isOverlayPresented = false
        self.isActive = true
        ensureOverlay()
        startFollowing()
        activateTarget()
        AppLog.log(.editor, "editor started for \(targetBundleID)")
    }

    public func finish() {
        stopFollowing()
        hideOverlay()
        isActive = false
        dragPreview = nil
        onFinished?(keymap)
        AppLog.log(.editor, "editor finished")
    }

    public func cancel() {
        stopFollowing()
        hideOverlay()
        isActive = false
        dragPreview = nil
        onCancelled?()
        AppLog.log(.editor, "editor cancelled")
    }

    public func bindKey(keyCode: UInt16, name: String) {
        guard let selectedID,
              let idx = keymap.elements.firstIndex(where: { $0.id == selectedID }),
              var button = keymap.elements[idx].buttonElement else {
            statusText = "Select a button first, then press a key"
            return
        }
        button.key = .virtual(keyCode, name: name)
        if case .draggableButton = keymap.elements[idx] {
            keymap.elements[idx] = .draggableButton(button)
        } else {
            keymap.elements[idx] = .button(button)
        }
        statusText = "Bound \(name)"
    }

    public func addButton(atNormalized point: CGPoint) {
        let button = ButtonElement(
            key: BoundKey(code: .unknown(-1), name: "?"),
            transform: NormalizedTransform(x: point.x, y: point.y, size: 0.06)
        )
        keymap.elements.append(.button(button))
        selectedID = button.id
        statusText = "Added button — press a key to bind"
    }

    public func deleteSelected() {
        guard let selectedID else { return }
        keymap.removeElement(id: selectedID)
        self.selectedID = nil
        dragPreview = nil
        statusText = "Deleted"
    }

    func displayedTransform(for button: ButtonElement) -> NormalizedTransform {
        if let dragPreview, dragPreview.id == button.id {
            return NormalizedTransform(x: dragPreview.x, y: dragPreview.y, size: button.transform.size)
        }
        return button.transform
    }

    func previewDrag(id: UUID, x: Double, y: Double) {
        if selectedID != id {
            selectedID = id
        }
        let preview = DragPreview(id: id, x: min(max(x, 0), 1), y: min(max(y, 0), 1))
        if dragPreview != preview {
            dragPreview = preview
        }
    }

    func endDrag() {
        guard let dragPreview else { return }
        applyTransform(id: dragPreview.id, x: dragPreview.x, y: dragPreview.y)
        self.dragPreview = nil
    }

    private func applyTransform(id: UUID, x: Double, y: Double) {
        guard let idx = keymap.elements.firstIndex(where: { $0.id == id }),
              var button = keymap.elements[idx].buttonElement else { return }
        button.transform.x = x
        button.transform.y = y
        if case .draggableButton = keymap.elements[idx] {
            keymap.elements[idx] = .draggableButton(button)
        } else {
            keymap.elements[idx] = .button(button)
        }
    }

    private func ensureOverlay() {
        if overlayWindow == nil {
            let window = EditorOverlayWindow(
                contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            window.isOpaque = false
            window.backgroundColor = .clear
            window.level = .floating
            window.ignoresMouseEvents = false
            window.hasShadow = false
            window.hidesOnDeactivate = false
            window.becomesKeyOnlyIfNeeded = true
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            window.contentView = NSHostingView(rootView: KeymapEditorRootView(controller: self))
            overlayWindow = window
        }
    }

    private func startFollowing() {
        followTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.syncOverlayPresentation(fromActivation: false)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        followTimer = timer

        if activationObserver == nil {
            activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.syncOverlayPresentation(fromActivation: true)
                }
            }
        }
        if appActiveObserver == nil {
            appActiveObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.syncOverlayPresentation(fromActivation: true)
                }
            }
        }

        syncOverlayPresentation(fromActivation: false)
    }

    private func stopFollowing() {
        followTimer?.invalidate()
        followTimer = nil
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
            self.activationObserver = nil
        }
        if let appActiveObserver {
            NotificationCenter.default.removeObserver(appActiveObserver)
            self.appActiveObserver = nil
        }
    }

    private func activateTarget() {
        guard let targetBundleID,
              let app = RunningAppCatalog.runningApplication(bundleID: targetBundleID) else {
            return
        }
        _ = app.activate(from: .current, options: [.activateAllWindows])
    }

    /// Overlay presentation policy:
    /// - Never become key / never activate Arkeys. Target stays frontmost so
    ///   the game window does not hide, and keys arrive via the global monitor.
    /// - Visible only while the target is the active app (above that window).
    /// - Hidden when Settings or any other app is active, so the mask cannot
    ///   cover those windows.
    /// - If a click on the overlay still activates Arkeys, bounce focus back
    ///   to the target. A click on Settings (or Cmd-Tab here) hides the mask.
    private func syncOverlayPresentation(fromActivation: Bool) {
        guard isActive else { return }
        guard let targetBundleID,
              let app = RunningAppCatalog.runningApplication(bundleID: targetBundleID),
              let frame = TargetResolver.primaryWindowFrame(for: app) else {
            if statusText != "Waiting for target window…" {
                statusText = "Waiting for target window…"
            }
            hideOverlay()
            return
        }

        let front = NSWorkspace.shared.frontmostApplication
        if front?.processIdentifier == app.processIdentifier {
            revealOverlay(at: frame)
            return
        }

        // Overlay click may activate Arkeys. Keep the mask up and bounce
        // focus back to the target so the game window does not hide.
        if isSelf(front), shouldReturnFocusToTarget() {
            if overlayWindow?.isVisible == true {
                moveOverlay(to: frame)
            }
            if fromActivation {
                activateTarget()
            }
            return
        }

        hideOverlay()
    }

    private func revealOverlay(at frame: NSRect) {
        guard let overlayWindow else { return }
        if overlayWindow.level != .floating {
            overlayWindow.level = .floating
        }
        moveOverlay(to: frame)
        // `setFrame(display: true)` can flip `isVisible` without bringing the
        // panel above the target — do not use it as the raise signal.
        if !isOverlayPresented {
            overlayWindow.orderFrontRegardless()
            isOverlayPresented = true
        }
    }

    private func moveOverlay(to frame: NSRect) {
        guard let overlayWindow else { return }
        if let lastOverlayFrame, lastOverlayFrame.nearlyEqual(frame) {
            return
        }
        overlayWindow.setFrame(frame, display: true)
        lastOverlayFrame = frame
    }

    private func hideOverlay() {
        lastOverlayFrame = nil
        isOverlayPresented = false
        guard let overlayWindow, overlayWindow.isVisible else { return }
        overlayWindow.orderOut(nil)
    }

    private func isSelf(_ app: NSRunningApplication?) -> Bool {
        guard let app else { return false }
        if let bundleID = app.bundleIdentifier, bundleID == Bundle.main.bundleIdentifier {
            return true
        }
        return app.processIdentifier == ProcessInfo.processInfo.processIdentifier
    }

    /// True when Arkeys was activated by interacting with the overlay, not Settings.
    private func shouldReturnFocusToTarget() -> Bool {
        guard let overlayWindow else { return false }
        if NSApp.currentEvent?.window === overlayWindow {
            return true
        }
        if NSApp.currentEvent?.window != nil {
            return false
        }
        let mouse = NSEvent.mouseLocation
        guard overlayWindow.frame.contains(mouse) else { return false }
        return !NSApp.windows.contains { window in
            window !== overlayWindow && window.isVisible && window.frame.contains(mouse)
        }
    }
}

/// Non-activating editor surface: never steals focus from the target.
/// Esc is a bindable key — dismiss only via Cancel / Done.
private final class EditorOverlayWindow: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {}
}

struct KeymapEditorRootView: View {
    @ObservedObject var controller: KeymapEditorController

    var body: some View {
        KeymapEditorCanvas(controller: controller)
    }
}

public struct KeymapEditorCanvas: View {
    @ObservedObject var controller: KeymapEditorController

    public init(controller: KeymapEditorController) {
        self.controller = controller
    }

    public var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                Color.black.opacity(0.18)
                    .contentShape(Rectangle())
                    .gesture(
                        SpatialTapGesture()
                            .onEnded { event in
                                let location = event.location
                                let nx = location.x / geo.size.width
                                let ny = location.y / geo.size.height
                                controller.addButton(atNormalized: CGPoint(x: nx, y: ny))
                            }
                    )

                ForEach(controller.keymap.elements) { element in
                    elementView(element, in: geo.size)
                }

                VStack(spacing: 8) {
                    HStack {
                        Text(controller.statusText)
                            .font(.caption)
                            .foregroundStyle(.white)
                            .padding(8)
                            .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
                        Spacer()
                        Button("Delete") { controller.deleteSelected() }
                        Button("Cancel") { controller.cancel() }
                        Button("Done") { controller.finish() }
                            .keyboardShortcut(.defaultAction)
                    }
                    .padding(10)
                    Spacer()
                }
            }
            .coordinateSpace(name: "keymapCanvas")
        }
    }

    @ViewBuilder
    private func elementView(_ element: KeymapElement, in size: CGSize) -> some View {
        switch element {
        case .button(let button), .draggableButton(let button):
            buttonNode(button, in: size, dimmed: false)
        case .joystick(let joy):
            unsupportedNode(
                id: joy.id,
                label: "JS",
                transform: joy.transform,
                in: size
            )
        case .mouseArea(let area):
            unsupportedNode(
                id: area.id,
                label: "Mouse",
                transform: area.transform,
                in: size
            )
        }
    }

    private func buttonNode(_ button: ButtonElement, in size: CGSize, dimmed: Bool) -> some View {
        let transform = controller.displayedTransform(for: button)
        let selected = controller.selectedID == button.id
        return keycap(button.key.name, selected: selected, dimmed: dimmed)
            .position(
                x: transform.x * size.width,
                y: transform.y * size.height
            )
            .gesture(
                DragGesture(minimumDistance: 2, coordinateSpace: .named("keymapCanvas"))
                    .onChanged { value in
                        controller.previewDrag(
                            id: button.id,
                            x: value.location.x / size.width,
                            y: value.location.y / size.height
                        )
                    }
                    .onEnded { _ in
                        controller.endDrag()
                    }
            )
            .onTapGesture {
                controller.selectedID = button.id
                controller.statusText = "Selected \(button.key.name) — press a key to rebind"
            }
    }

    private func unsupportedNode(id: UUID, label: String, transform: NormalizedTransform, in size: CGSize) -> some View {
        keycap(label, selected: false, dimmed: true)
            .position(x: transform.x * size.width, y: transform.y * size.height)
            .allowsHitTesting(false)
    }

    private func keycap(_ title: String, selected: Bool, dimmed: Bool) -> some View {
        let fill = dimmed
            ? KeycapChrome.dimmedFill
            : (selected ? KeycapChrome.selectedFill : KeycapChrome.fill)
        let stroke = selected ? Color.white : Color.white.opacity(0.92)
        return Text(title)
            .font(.system(size: KeycapChrome.fontSize, weight: .regular))
            .foregroundStyle(.white)
            .minimumScaleFactor(0.6)
            .lineLimit(1)
            .padding(.horizontal, controller.buttonShape == .rectangle ? KeycapChrome.horizontalPadding : 0)
            .padding(.vertical, controller.buttonShape == .rectangle ? KeycapChrome.verticalPadding : 0)
            .frame(minWidth: KeycapChrome.minSide, minHeight: KeycapChrome.minSide)
            .frame(
                width: controller.buttonShape == .circle ? KeycapChrome.minSide : nil,
                height: controller.buttonShape == .circle ? KeycapChrome.minSide : nil
            )
            .background(keyChrome(fill: fill, stroke: stroke, lineWidth: selected ? 1.5 : 1))
            .shadow(color: .black.opacity(0.28), radius: 1.5, y: 1)
    }

    @ViewBuilder
    private func keyChrome(fill: Color, stroke: Color, lineWidth: CGFloat) -> some View {
        switch controller.buttonShape {
        case .circle:
            Circle()
                .fill(fill)
                .overlay(Circle().stroke(stroke, lineWidth: lineWidth))
        case .rectangle:
            RoundedRectangle(cornerRadius: KeycapChrome.cornerRadius, style: .continuous)
                .fill(fill)
                .overlay(
                    RoundedRectangle(cornerRadius: KeycapChrome.cornerRadius, style: .continuous)
                        .stroke(stroke, lineWidth: lineWidth)
                )
        }
    }
}

private enum KeycapChrome {
    static let fontSize: CGFloat = 11
    static let minSide: CGFloat = 22
    static let horizontalPadding: CGFloat = 7
    static let verticalPadding: CGFloat = 3
    static let cornerRadius: CGFloat = 1
    static let fill = Color(white: 0.22)
    static let selectedFill = Color(white: 0.32)
    static let dimmedFill = Color(white: 0.22).opacity(0.45)
}

private extension CGRect {
    func nearlyEqual(_ other: CGRect) -> Bool {
        abs(origin.x - other.origin.x) < 0.5
            && abs(origin.y - other.origin.y) < 0.5
            && abs(width - other.width) < 0.5
            && abs(height - other.height) < 0.5
    }
}
