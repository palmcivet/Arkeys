import Foundation
import AppKit
import SwiftUI
import Combine
import KeymapCore
import Targeting

@MainActor
public final class KeymapEditorController: ObservableObject {
    /// Carbon `kVK_Escape`.
    public static let escapeKeyCode: UInt16 = 53

    @Published public var keymap: CanonicalKeymap
    @Published public var selectedID: UUID?
    @Published public var isActive: Bool = false
    @Published public var windowFrame: CGRect = .zero
    @Published public var statusText: String = "Click empty area to add a button · drag to move · press a key to bind"

    private var overlayWindow: NSWindow?
    private var followTimer: Timer?
    private var targetBundleID: String?
    private var baselineKeymap: CanonicalKeymap = CanonicalKeymap()
    private var isPromptingDiscard = false
    public var onFinished: ((CanonicalKeymap) -> Void)?
    public var onCancelled: (() -> Void)?

    public var hasUnsavedChanges: Bool {
        keymap != baselineKeymap
    }

    public init(keymap: CanonicalKeymap = CanonicalKeymap()) {
        self.keymap = keymap
    }

    public func start(targetBundleID: String, keymap: CanonicalKeymap) {
        self.targetBundleID = targetBundleID
        self.keymap = keymap
        self.baselineKeymap = keymap
        self.selectedID = nil
        self.isActive = true
        ensureOverlay()
        startFollowing()
        overlayWindow?.makeKeyAndOrderFront(nil)
        InjectLog.editor("editor started for \(targetBundleID)")
    }

    public func finish() {
        stopFollowing()
        overlayWindow?.orderOut(nil)
        isActive = false
        onFinished?(keymap)
        InjectLog.editor("editor finished")
    }

    public func cancel() {
        stopFollowing()
        overlayWindow?.orderOut(nil)
        isActive = false
        onCancelled?()
        InjectLog.editor("editor cancelled")
    }

    /// Escape / Cmd+.: discard immediately if clean; confirm when there are unsaved edits.
    /// Explicit Cancel button calls `cancel()` directly — no second prompt (intentional dismiss).
    public func requestCancel() {
        guard isActive else { return }
        guard hasUnsavedChanges else {
            cancel()
            return
        }
        guard !isPromptingDiscard else { return }
        isPromptingDiscard = true

        let alert = NSAlert()
        alert.messageText = String(localized: "keymap.discard.title", bundle: .main)
        alert.informativeText = String(localized: "keymap.discard.message", bundle: .main)
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "keymap.discard.confirm", bundle: .main))
        alert.addButton(withTitle: String(localized: "keymap.discard.keepEditing", bundle: .main))

        let response = alert.runModal()
        isPromptingDiscard = false
        if response == .alertFirstButtonReturn {
            cancel()
        }
    }

    /// Key events while editing: Escape cancels (with dirty check); other keys bind.
    public func handleKeyDown(keyCode: UInt16, name: String) {
        if keyCode == Self.escapeKeyCode {
            requestCancel()
            return
        }
        bindKey(keyCode: keyCode, name: name)
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
        statusText = "Deleted"
    }

    public func updateTransform(id: UUID, x: Double, y: Double) {
        guard let idx = keymap.elements.firstIndex(where: { $0.id == id }),
              var button = keymap.elements[idx].buttonElement else { return }
        button.transform.x = min(max(x, 0), 1)
        button.transform.y = min(max(y, 0), 1)
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
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            window.editor = self
            window.isOpaque = false
            window.backgroundColor = .clear
            window.level = .floating
            window.ignoresMouseEvents = false
            window.hasShadow = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.contentView = NSHostingView(rootView: KeymapEditorRootView(controller: self))
            overlayWindow = window
        }
    }

    private func startFollowing() {
        followTimer?.invalidate()
        // Track move/resize even while the editor overlay is key (target is not focused).
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.syncOverlayFrame()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        followTimer = timer
        syncOverlayFrame()
    }

    private func stopFollowing() {
        followTimer?.invalidate()
        followTimer = nil
    }

    private func syncOverlayFrame() {
        guard let targetBundleID,
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: targetBundleID).first,
              let frame = TargetResolver.primaryWindowFrame(for: app) else {
            statusText = "Waiting for target window…"
            return
        }
        windowFrame = frame
        overlayWindow?.setFrame(frame, display: true)
    }
}

private enum InjectLog {
    static func editor(_ message: String) {
        print("[Arkeys][editor] \(message)")
    }
}

/// Borderless editor surface: Esc / Cmd+. → discard confirm, not silent close.
private final class EditorOverlayWindow: NSWindow {
    weak var editor: KeymapEditorController?

    override func cancelOperation(_ sender: Any?) {
        editor?.requestCancel()
    }
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
        let diameter = max(36, size.width * button.transform.size)
        let selected = controller.selectedID == button.id
        return Text(button.key.name)
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: diameter, height: diameter)
            .background(
                Circle()
                    .fill(selected ? Color.accentColor.opacity(0.85) : Color.blue.opacity(dimmed ? 0.35 : 0.7))
            )
            .overlay(Circle().stroke(selected ? Color.white : Color.clear, lineWidth: 2))
            .position(
                x: button.transform.x * size.width,
                y: button.transform.y * size.height
            )
            .gesture(
                DragGesture(minimumDistance: 2, coordinateSpace: .named("keymapCanvas"))
                    .onChanged { value in
                        controller.selectedID = button.id
                        let nx = value.location.x / size.width
                        let ny = value.location.y / size.height
                        controller.updateTransform(id: button.id, x: nx, y: ny)
                    }
            )
            .onTapGesture {
                controller.selectedID = button.id
                controller.statusText = "Selected \(button.key.name) — press a key to rebind"
            }
    }

    private func unsupportedNode(id: UUID, label: String, transform: NormalizedTransform, in size: CGSize) -> some View {
        let diameter = max(40, size.width * transform.size * 0.4)
        return Text(label)
            .font(.caption2)
            .foregroundStyle(.white.opacity(0.8))
            .frame(width: diameter, height: diameter)
            .background(Circle().strokeBorder(Color.white.opacity(0.5), lineWidth: 1).background(Circle().fill(Color.gray.opacity(0.25))))
            .position(x: transform.x * size.width, y: transform.y * size.height)
            .allowsHitTesting(false)
    }
}
