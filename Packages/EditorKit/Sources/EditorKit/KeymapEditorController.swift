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
    var size: Double
}

@MainActor
public final class KeymapEditorController: ObservableObject {
    @Published public var keymap: CanonicalKeymap
    @Published public var selectedID: UUID?
    @Published public var isActive: Bool = false
    @Published public var buttonShape: KeymapButtonShape = .circle
    @Published public var statusText: String = EditorChromeCopy.english.idleStatus
    @Published var chromeEdge: EditorChromeEdge = .bottom
    @Published private var dragPreview: DragPreview?
    public var chromeCopy = EditorChromeCopy.english

    private var overlayWindow: NSWindow?
    private var followTimer: Timer?
    private var activationObserver: NSObjectProtocol?
    private var appActiveObserver: NSObjectProtocol?
    private var targetBundleID: String?
    private var lastOverlayFrame: CGRect?
    private var isOverlayPresented = false
    private var canvasSize: CGSize = .zero
    var chromeBarSize: CGSize = EditorChromeDodge.estimatedBarSize

    public var onFinished: ((CanonicalKeymap) -> Void)?
    public var onCancelled: (() -> Void)?
    /// True while the host status-item menu is open. Keep the overlay up and
    /// do not bounce focus back to the target (that would dismiss the menu).
    public var isStatusMenuTracking = false {
        didSet {
            guard isActive, oldValue != isStatusMenuTracking else { return }
            syncOverlayPresentation(fromActivation: false)
        }
    }
    /// Host Settings (or other Arkeys UI) is key — hide so the mask cannot cover it.
    public var shouldHideForHostUI: () -> Bool = { false }

    public init(keymap: CanonicalKeymap = CanonicalKeymap()) {
        self.keymap = keymap
    }

    public func start(targetBundleID: String, keymap: CanonicalKeymap) {
        self.targetBundleID = targetBundleID
        self.keymap = keymap
        self.selectedID = nil
        self.dragPreview = nil
        self.chromeEdge = .bottom
        self.lastOverlayFrame = nil
        self.isOverlayPresented = false
        self.canvasSize = .zero
        self.chromeBarSize = EditorChromeDodge.estimatedBarSize
        self.isActive = true
        setStatus(chromeCopy.idleStatus)
        ensureOverlay()
        startFollowing()
        activateTarget()
        AppLog.log(.editor, "editor started for \(targetBundleID)")
    }

    public func finish() {
        endSession()
        onFinished?(keymap)
        AppLog.log(.editor, "editor finished")
    }

    public func cancel() {
        endSession()
        onCancelled?()
        AppLog.log(.editor, "editor cancelled")
    }

    public func bindKey(keyCode: UInt16, name: String) {
        guard let selectedID, var button = button(id: selectedID) else {
            setStatus(chromeCopy.selectButtonFirst)
            return
        }
        button.key = .virtual(keyCode, name: name)
        keymap.upsertButton(button)
        setStatus(chromeCopy.boundStatus(name: name))
    }

    public func addButton(atNormalized point: CGPoint) {
        let button = ButtonElement(
            key: BoundKey(code: .unknown(-1), name: "?"),
            transform: NormalizedTransform(x: point.x, y: point.y, size: NormalizedTransform.defaultSize)
        )
        keymap.elements.append(.button(button))
        selectedID = button.id
        setStatus(chromeCopy.selectedStatus(name: button.key.name))
    }

    func deleteElement(id: UUID) {
        keymap.removeElement(id: id)
        if selectedID == id {
            selectedID = nil
        }
        if dragPreview?.id == id {
            dragPreview = nil
        }
        setStatus(chromeCopy.deleted)
    }

    func select(_ button: ButtonElement) {
        selectedID = button.id
        setStatus(chromeCopy.selectedStatus(name: button.key.name))
    }

    func displayedTransform(for button: ButtonElement) -> NormalizedTransform {
        if let dragPreview, dragPreview.id == button.id {
            return NormalizedTransform(x: dragPreview.x, y: dragPreview.y, size: dragPreview.size)
        }
        return button.transform
    }

    func previewDrag(id: UUID, x: Double, y: Double) {
        guard let button = button(id: id) else { return }
        if selectedID != id {
            select(button)
        }
        let preview = DragPreview(
            id: id,
            x: min(max(x, 0), 1),
            y: min(max(y, 0), 1),
            size: button.transform.size
        )
        if dragPreview != preview {
            dragPreview = preview
            refreshChromeEdge()
        }
    }

    func previewResize(id: UUID, canvasLocation: CGPoint, canvas: CGSize) {
        guard let button = button(id: id) else { return }
        if selectedID != id {
            select(button)
        }
        let reference = EditorHandleLayout.resizeReference(title: button.key.name, shape: buttonShape)
        let size = EditorHandleLayout.sizeAfterCornerResize(
            cursorX: Double(canvasLocation.x),
            cursorY: Double(canvasLocation.y),
            centerX: button.transform.x * Double(canvas.width),
            centerY: button.transform.y * Double(canvas.height),
            unscaledWidth: reference.width,
            unscaledHeight: reference.height,
            minScale: Double(KeycapChrome.minScale),
            maxScale: Double(KeycapChrome.maxScale)
        )
        let preview = DragPreview(id: id, x: button.transform.x, y: button.transform.y, size: size)
        if dragPreview != preview {
            dragPreview = preview
            refreshChromeEdge()
        }
    }

    func endDrag() {
        guard let dragPreview else { return }
        applyTransform(id: dragPreview.id, x: dragPreview.x, y: dragPreview.y, size: dragPreview.size)
        if let name = button(id: dragPreview.id)?.key.name {
            setStatus(chromeCopy.selectedStatus(name: name))
        }
        self.dragPreview = nil
        refreshChromeEdge()
    }

    func noteChromeMetrics(canvas: CGSize, barSize: CGSize) {
        let canvasChanged = canvas != canvasSize
        let barChanged = barSize != chromeBarSize && barSize.width > 0 && barSize.height > 0
        if canvasChanged {
            canvasSize = canvas
        }
        if barChanged {
            chromeBarSize = barSize
        }
        if canvasChanged || barChanged {
            refreshChromeEdge()
        }
    }

    private func endSession() {
        stopFollowing()
        hideOverlay()
        isActive = false
        dragPreview = nil
        chromeEdge = .bottom
        canvasSize = .zero
        isStatusMenuTracking = false
    }

    private func applyTransform(id: UUID, x: Double, y: Double, size: Double) {
        updateButton(id: id) { button in
            button.transform = NormalizedTransform(x: x, y: y, size: size)
        }
    }

    private func button(id: UUID) -> ButtonElement? {
        keymap.elements.first { $0.id == id }?.buttonElement
    }

    private func updateButton(id: UUID, mutate: (inout ButtonElement) -> Void) {
        guard var button = button(id: id) else { return }
        mutate(&button)
        keymap.upsertButton(button)
    }

    /// Normalized canvas step for VoiceOver / keyboard nudge actions.
    static let nudgeStep = 0.02
    /// Uniform scale applied by the resize handle's increment / decrement actions.
    static let sizeFactor = 1.1

    func nudge(id: UUID, dx: Double, dy: Double) {
        guard let button = button(id: id) else { return }
        if selectedID != id {
            select(button)
        }
        applyTransform(
            id: id,
            x: min(max(button.transform.x + dx * Self.nudgeStep, 0), 1),
            y: min(max(button.transform.y + dy * Self.nudgeStep, 0), 1),
            size: button.transform.size
        )
        refreshChromeEdge()
    }

    func adjustSize(id: UUID, factor: Double) {
        guard let button = button(id: id) else { return }
        if selectedID != id {
            select(button)
        }
        applyTransform(
            id: id,
            x: button.transform.x,
            y: button.transform.y,
            size: button.transform.size * factor
        )
        refreshChromeEdge()
    }

    private func setStatus(_ text: String) {
        if statusText != text {
            statusText = text
            announceStatus(text)
        }
        refreshChromeEdge()
    }

    private func announceStatus(_ text: String) {
        guard let overlayWindow else { return }
        NSAccessibility.post(
            element: overlayWindow,
            notification: .announcementRequested,
            userInfo: [
                .announcement: text,
                NSAccessibility.NotificationUserInfoKey(rawValue: "NSAccessibilityAnnouncementPriorityKey"):
                    NSAccessibilityPriorityLevel.medium,
            ]
        )
    }

    private func refreshChromeEdge() {
        let next = EditorChromeDodge.resolve(
            current: chromeEdge,
            canvas: canvasSize,
            barSize: chromeBarSize,
            obstacles: chromeObstacles(in: canvasSize)
        )
        if next != chromeEdge {
            chromeEdge = next
        }
    }

    func chromeObstacles(in canvas: CGSize) -> [CGRect] {
        guard canvas.width > 0, canvas.height > 0 else { return [] }
        let id = dragPreview?.id ?? selectedID
        guard let id, let target = button(id: id) else { return [] }
        let transform = displayedTransform(for: target)
        return [
            EditorChromeDodge.keycapFrame(
                centerX: CGFloat(transform.x) * canvas.width,
                centerY: CGFloat(transform.y) * canvas.height,
                title: target.key.name,
                shape: buttonShape,
                scale: KeycapChrome.scale(for: transform.size)
            )
        ]
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
    /// - Visible while the target is frontmost, or while the status-item menu
    ///   is open (hiding would bounce focus and dismiss the menu).
    /// - Hidden when Settings is visible or another app is active. Hovering
    ///   the target while Arkeys is frontmost must not raise the mask over
    ///   host windows.
    /// - A real overlay click (event window is the panel) bounces focus back.
    private func syncOverlayPresentation(fromActivation: Bool) {
        guard isActive else { return }
        guard let targetBundleID,
              let app = RunningAppCatalog.runningApplication(bundleID: targetBundleID),
              let frame = TargetResolver.primaryWindowFrame(for: app) else {
            if statusText != chromeCopy.waitingStatus {
                setStatus(chromeCopy.waitingStatus)
            }
            hideOverlay()
            return
        }

        let front = NSWorkspace.shared.frontmostApplication
        let decision = EditorOverlayPolicy.decide(
            targetIsFrontmost: front?.processIdentifier == app.processIdentifier,
            hostIsFrontmost: isSelf(front),
            hideForHostUI: shouldHideForHostUI(),
            statusMenuTracking: isStatusMenuTracking,
            overlayInteraction: isOverlayInteraction()
        )
        switch decision {
        case .hide:
            hideOverlay()
        case .show:
            revealOverlay(at: frame)
        case .showAndReturnFocus:
            revealOverlay(at: frame)
            if fromActivation {
                activateTarget()
            }
        }
    }

    private func revealOverlay(at frame: NSRect) {
        guard overlayWindow != nil else { return }
        moveOverlay(to: frame)
        // `setFrame(display: true)` can flip `isVisible` without bringing the
        // panel above the target — do not use it as the raise signal.
        if !isOverlayPresented {
            overlayWindow?.orderFrontRegardless()
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

    /// True only for a click/drag that landed on the overlay panel.
    /// Mouse location alone is not enough — hover must not raise the mask
    /// over Settings while Arkeys is frontmost.
    private func isOverlayInteraction() -> Bool {
        guard let overlayWindow else { return false }
        return NSApp.currentEvent?.window === overlayWindow
    }
}

/// Non-activating editor surface: never steals focus from the target.
/// Esc is a bindable key — dismiss only via Cancel / Done / the menu bar.
private final class EditorOverlayWindow: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {}
}

private struct EditorChromeBarSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next.width > 0, next.height > 0 {
            value = next
        }
    }
}

private struct EditorChromeContentWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        if next > 0 {
            value = next
        }
    }
}

struct KeymapEditorRootView: View {
    @ObservedObject var controller: KeymapEditorController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let canvas = geo.size
            let barHeight = max(controller.chromeBarSize.height, EditorChromeDodge.islandHeight)
            let barY = EditorChromeDodge.barCenterY(
                edge: controller.chromeEdge,
                canvas: canvas,
                barHeight: barHeight
            )
            ZStack {
                KeymapEditorCanvas(controller: controller)
                KeymapEditorChromeBar(controller: controller, canvasWidth: canvas.width)
                    .background {
                        GeometryReader { bar in
                            Color.clear.preference(key: EditorChromeBarSizeKey.self, value: bar.size)
                        }
                    }
                    .position(x: canvas.width / 2, y: barY)
            }
            .onAppear {
                controller.noteChromeMetrics(canvas: canvas, barSize: controller.chromeBarSize)
            }
            .onChange(of: canvas) { _, newSize in
                controller.noteChromeMetrics(canvas: newSize, barSize: controller.chromeBarSize)
            }
            .onPreferenceChange(EditorChromeBarSizeKey.self) { size in
                controller.noteChromeMetrics(canvas: canvas, barSize: size)
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.24), value: controller.chromeEdge)
        }
    }
}

/// Compact dark island — CleanShot / annotation-bar language, not a Tahoe search field.
private struct KeymapEditorChromeBar: View {
    @ObservedObject var controller: KeymapEditorController
    var canvasWidth: CGFloat
    @State private var contentWidth: CGFloat = 0

    var body: some View {
        let width = EditorChromeDodge.fittedBarWidth(
            canvasWidth: canvasWidth,
            contentWidth: contentWidth
        )
        EditorChromeBarContent(
            statusText: controller.statusText,
            copy: controller.chromeCopy,
            expandStatus: true,
            onCancel: { controller.cancel() },
            onDone: { controller.finish() }
        )
        .accessibilityAction(named: Text(controller.chromeCopy.addKey)) {
            controller.addButton(atNormalized: CGPoint(x: 0.5, y: 0.5))
        }
        .frame(width: width)
        .background {
            EditorChromeBarContent(
                statusText: controller.statusText,
                copy: controller.chromeCopy,
                expandStatus: false,
                onCancel: {},
                onDone: {}
            )
            .fixedSize(horizontal: true, vertical: false)
            .hidden()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .overlay {
                GeometryReader { geo in
                    Color.clear.preference(key: EditorChromeContentWidthKey.self, value: geo.size.width)
                }
            }
        }
        .onPreferenceChange(EditorChromeContentWidthKey.self) { measured in
            guard measured > 0, measured != contentWidth else { return }
            contentWidth = measured
        }
    }
}

private struct EditorChromeBarContent: View {
    var statusText: String
    var copy: EditorChromeCopy
    var expandStatus: Bool
    var onCancel: () -> Void
    var onDone: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Text(statusText)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: expandStatus ? .infinity : nil, alignment: .leading)
                .padding(.leading, 12)
                .padding(.trailing, 10)
                .padding(.vertical, 8)

            EditorChromeHairline()

            HStack(spacing: 4) {
                Button(action: onCancel) {
                    Text(copy.cancel)
                }
                .buttonStyle(EditorChromeButtonStyle(prominent: false))

                Button(action: onDone) {
                    Text(copy.done)
                }
                .buttonStyle(EditorChromeButtonStyle(prominent: true))
            }
            .fixedSize()
            .padding(.horizontal, 7)
            .padding(.vertical, 6)
        }
        .background { EditorChromeMaterial(cornerRadius: 10) }
        .environment(\.colorScheme, .dark)
    }
}

private struct EditorChromeHairline: View {
    var body: some View {
        Rectangle()
            .fill(.white.opacity(0.12))
            .frame(width: 1, height: 14)
            .accessibilityHidden(true)
    }
}

/// Dark HUD plate: material + scrim so light mode cannot bleach it into a search field.
private struct EditorChromeMaterial: View {
    var cornerRadius: CGFloat
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let strokeOpacity = contrast == .increased ? 0.32 : 0.10
        let strokeWidth: CGFloat = contrast == .increased ? 1 : 0.5
        Group {
            if reduceTransparency {
                shape.fill(Color(white: 0.14))
            } else {
                shape
                    .fill(.ultraThinMaterial)
                    .overlay { shape.fill(Color.black.opacity(0.38)) }
            }
        }
        .shadow(color: .black.opacity(reduceTransparency ? 0.18 : 0.32), radius: 12, y: 3)
        .overlay { shape.strokeBorder(Color.white.opacity(strokeOpacity), lineWidth: strokeWidth) }
        .accessibilityHidden(true)
    }
}

private struct EditorChromeButtonStyle: ButtonStyle {
    var prominent: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: prominent ? .semibold : .regular))
            .foregroundStyle(prominent ? Color.white : Color.primary.opacity(0.88))
            .padding(.horizontal, prominent ? 10 : 8)
            .padding(.vertical, 4)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(prominent ? Color.accentColor : Color.white.opacity(configuration.isPressed ? 0.14 : 0.08))
            }
            .opacity(configuration.isPressed ? 0.86 : 1)
    }
}

public struct KeymapEditorCanvas: View {
    @ObservedObject var controller: KeymapEditorController

    public init(controller: KeymapEditorController) {
        self.controller = controller
    }

    public var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.opacity(0.18)
                    .contentShape(Rectangle())
                    .accessibilityHidden(true)
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
            }
            .coordinateSpace(name: "keymapCanvas")
        }
    }

    @ViewBuilder
    private func elementView(_ element: KeymapElement, in size: CGSize) -> some View {
        switch element {
        case .button(let button), .draggableButton(let button):
            buttonNode(button, in: size)
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

    private func buttonNode(_ button: ButtonElement, in size: CGSize) -> some View {
        let transform = controller.displayedTransform(for: button)
        let selected = controller.selectedID == button.id
        return KeymapEditorNode(
            title: button.key.name,
            shape: controller.buttonShape,
            style: selected ? .selected : .normal,
            scale: KeycapChrome.scale(for: transform.size),
            copy: controller.chromeCopy,
            onDelete: { controller.deleteElement(id: button.id) },
            onSelect: { controller.select(button) },
            onMove: { location in
                controller.previewDrag(
                    id: button.id,
                    x: location.x / size.width,
                    y: location.y / size.height
                )
            },
            onResize: { location in
                controller.previewResize(
                    id: button.id,
                    canvasLocation: location,
                    canvas: size
                )
            },
            onGestureEnd: { controller.endDrag() },
            onNudge: { dx, dy in
                controller.nudge(id: button.id, dx: dx, dy: dy)
            },
            onAdjustSize: { factor in
                controller.adjustSize(id: button.id, factor: factor)
            }
        )
        .position(
            x: transform.x * size.width,
            y: transform.y * size.height
        )
    }

    private func unsupportedNode(id: UUID, label: String, transform: NormalizedTransform, in size: CGSize) -> some View {
        KeymapKeycap(
            title: label,
            shape: controller.buttonShape,
            style: .dimmed,
            scale: KeycapChrome.scale(for: transform.size)
        )
            .position(x: transform.x * size.width, y: transform.y * size.height)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

}
