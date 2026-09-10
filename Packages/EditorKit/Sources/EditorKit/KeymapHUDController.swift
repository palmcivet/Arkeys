import Foundation
import AppKit
import SwiftUI
import KeymapCore
import Targeting

/// Click-through overlay that keeps keymap labels on the target window.
///
/// Hide while the target window is moved/resized (AX events), then sample
/// the frame once after those events settle.
@MainActor
public final class KeymapHUDController: ObservableObject {
    @Published public var keymap: CanonicalKeymap = CanonicalKeymap()
    @Published public var buttonShape: KeymapButtonShape = .circle

    private var overlayWindow: NSWindow?
    private var activationObserver: NSObjectProtocol?
    private var spaceObserver: NSObjectProtocol?
    private var screenObserver: NSObjectProtocol?
    private let geometryWatcher = AXWindowGeometryWatcher()
    private var watchedPID: pid_t?

    private var isRunning = false
    private var isWindowTransforming = false
    private var settleWork: DispatchWorkItem?
    private var targetBundleID: String?
    private var lastOverlayFrame: CGRect?
    private var isOverlayPresented = false

    private static let transformSettle: TimeInterval = 0.18

    public init() {
        geometryWatcher.onChanging = { [weak self] in
            MainActor.assumeIsolated {
                self?.beginTransform()
            }
        }
    }

    deinit {
        settleWork?.cancel()
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
        if let spaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(spaceObserver)
        }
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
    }

    public func updateAppearance(keymap: CanonicalKeymap, buttonShape: KeymapButtonShape) {
        guard self.keymap != keymap || self.buttonShape != buttonShape else { return }
        self.keymap = keymap
        self.buttonShape = buttonShape
        if isRunning, !isWindowTransforming {
            syncOverlayPresentation()
        }
    }

    public func start(targetBundleID: String) {
        let targetChanged = self.targetBundleID != targetBundleID
        self.targetBundleID = targetBundleID

        if isRunning, !targetChanged {
            if !isWindowTransforming {
                syncOverlayPresentation()
            }
            return
        }

        if isRunning {
            stopFollowing()
        }
        isRunning = true
        ensureOverlay()
        startFollowing()
    }

    public func stop() {
        guard isRunning else { return }
        isRunning = false
        isWindowTransforming = false
        targetBundleID = nil
        settleWork?.cancel()
        settleWork = nil
        stopFollowing()
        hideOverlay()
    }

    private func ensureOverlay() {
        guard overlayWindow == nil else { return }
        let window = HUDOverlayWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.ignoresMouseEvents = true
        window.hasShadow = false
        window.hidesOnDeactivate = false
        window.becomesKeyOnlyIfNeeded = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        window.contentView = NSHostingView(rootView: KeymapHUDView(controller: self))
        overlayWindow = window
    }

    private func startFollowing() {
        observeWorkspace(NSWorkspace.didActivateApplicationNotification, stored: &activationObserver)
        observeWorkspace(NSWorkspace.activeSpaceDidChangeNotification, stored: &spaceObserver)
        if screenObserver == nil {
            screenObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.handleWorkspaceChange()
                }
            }
        }
        syncOverlayPresentation()
    }

    private func observeWorkspace(_ name: NSNotification.Name, stored: inout NSObjectProtocol?) {
        guard stored == nil else { return }
        stored = NSWorkspace.shared.notificationCenter.addObserver(
            forName: name,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleWorkspaceChange()
            }
        }
    }

    private func stopFollowing() {
        settleWork?.cancel()
        settleWork = nil
        detachGeometryWatch()
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
            self.activationObserver = nil
        }
        if let spaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(spaceObserver)
            self.spaceObserver = nil
        }
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }
    }

    private func handleWorkspaceChange() {
        isWindowTransforming = false
        settleWork?.cancel()
        settleWork = nil
        syncOverlayPresentation()
    }

    private func beginTransform() {
        guard isRunning else { return }
        if !isWindowTransforming {
            isWindowTransforming = true
            hideOverlay(clearFrame: false)
        }
        scheduleSettle()
    }

    private func scheduleSettle() {
        settleWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.endTransform()
            }
        }
        settleWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.transformSettle, execute: work)
    }

    private func endTransform() {
        settleWork?.cancel()
        settleWork = nil
        isWindowTransforming = false
        syncOverlayPresentation()
    }

    private func syncOverlayPresentation() {
        guard isRunning, !isWindowTransforming else { return }
        guard !keymap.elements.isEmpty,
              let targetBundleID,
              let app = RunningAppCatalog.runningApplication(bundleID: targetBundleID),
              let frame = TargetResolver.primaryWindowFrame(for: app),
              NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier
        else {
            detachGeometryWatch()
            hideOverlay()
            return
        }

        attachGeometryWatch(pid: app.processIdentifier)
        revealOverlay(at: frame)
    }

    private func attachGeometryWatch(pid: pid_t) {
        guard watchedPID != pid else { return }
        geometryWatcher.watch(pid: pid)
        watchedPID = pid
    }

    private func detachGeometryWatch() {
        geometryWatcher.stop()
        watchedPID = nil
    }

    private func revealOverlay(at frame: NSRect) {
        guard let overlayWindow else { return }
        moveOverlay(to: frame)
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

    private func hideOverlay(clearFrame: Bool = true) {
        if clearFrame {
            lastOverlayFrame = nil
        }
        isOverlayPresented = false
        guard let overlayWindow, overlayWindow.isVisible else { return }
        overlayWindow.orderOut(nil)
    }
}

private final class HUDOverlayWindow: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {}
}

private struct KeymapHUDView: View {
    @ObservedObject var controller: KeymapHUDController

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(controller.keymap.elements) { element in
                    elementView(element, in: geo.size)
                }
            }
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func elementView(_ element: KeymapElement, in size: CGSize) -> some View {
        switch element {
        case .button(let button), .draggableButton(let button):
            hudKeycap(title: button.key.name, transform: button.transform, in: size, style: .overlay)
        case .joystick(let joy):
            hudKeycap(title: "JS", transform: joy.transform, in: size, style: .overlayDimmed)
        case .mouseArea(let area):
            hudKeycap(title: "Mouse", transform: area.transform, in: size, style: .overlayDimmed)
        }
    }

    private func hudKeycap(
        title: String,
        transform: NormalizedTransform,
        in size: CGSize,
        style: KeymapKeycap.Style
    ) -> some View {
        KeymapKeycap(
            title: title,
            shape: controller.buttonShape,
            style: style,
            scale: KeycapChrome.scale(for: transform.size)
        )
        .position(x: transform.x * size.width, y: transform.y * size.height)
    }
}
