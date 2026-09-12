import SwiftUI
import KeymapCore

struct KeymapEditorNode: View {
    let title: String
    let shape: KeymapButtonShape
    let style: KeymapKeycap.Style
    let scale: CGFloat
    var copy: EditorChromeCopy = .english
    let onDelete: () -> Void
    let onSelect: () -> Void
    let onMove: (CGPoint) -> Void
    let onResize: (CGPoint) -> Void
    let onGestureEnd: () -> Void
    let onNudge: (Double, Double) -> Void
    let onAdjustSize: (Double) -> Void

    private var isSelected: Bool { style == .selected }

    var body: some View {
        let box = KeycapChrome.fittedSize(title: title, shape: shape, scale: scale)
        let pad = EditorHandleLayout.pad
        let pull = EditorHandleLayout.pull(box: box, shape: shape, scale: scale)
        ZStack {
            KeymapKeycap(title: title, shape: shape, style: style, scale: scale)
                .contentShape(Rectangle())
                .gesture(moveGesture)
                .onTapGesture(perform: onSelect)
        }
        // Keep this above the overlays so delete / resize stay their own VoiceOver elements.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityHint(copy.keyHint)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : [.isButton])
        .accessibilityAction {
            onSelect()
        }
        .accessibilityAction(named: Text(copy.moveLeft)) { onNudge(-1, 0) }
        .accessibilityAction(named: Text(copy.moveRight)) { onNudge(1, 0) }
        .accessibilityAction(named: Text(copy.moveUp)) { onNudge(0, -1) }
        .accessibilityAction(named: Text(copy.moveDown)) { onNudge(0, 1) }
        .frame(width: box.width + pad * 2, height: box.height + pad * 2)
        .overlay(alignment: .topLeading) {
            if isSelected {
                EditorDeleteHandle(copy: copy, action: onDelete)
                    .offset(x: pull.width, y: pull.height)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if isSelected {
                EditorResizeHandle(
                    copy: copy,
                    scale: scale,
                    onChanged: onResize,
                    onEnded: onGestureEnd,
                    onAdjustSize: onAdjustSize
                )
                    .offset(x: -pull.width, y: -pull.height)
            }
        }
    }

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named("keymapCanvas"))
            .onChanged { value in
                onMove(value.location)
            }
            .onEnded { _ in
                onGestureEnd()
            }
    }
}

private struct EditorDeleteHandle: View {
    let copy: EditorChromeCopy
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            EditorHandleChrome(systemName: "xmark")
                .padding(4)
                .contentShape(Circle())
                .padding(-4)
        }
        .buttonStyle(.plain)
        .help(copy.deleteHelp)
        .accessibilityLabel(copy.deleteKey)
    }
}

private struct EditorResizeHandle: View {
    let copy: EditorChromeCopy
    let scale: CGFloat
    let onChanged: (CGPoint) -> Void
    let onEnded: () -> Void
    let onAdjustSize: (Double) -> Void

    private var sizePercent: Int {
        Int((Double(scale) * 100).rounded())
    }

    var body: some View {
        EditorHandleChrome(systemName: "arrow.up.left.and.arrow.down.right")
            .padding(4)
            .contentShape(Circle())
            .padding(-4)
            .help(copy.resizeHelp)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(copy.resizeKey)
            .accessibilityValue("\(sizePercent)%")
            .accessibilityHint(copy.resizeHint)
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment:
                    onAdjustSize(KeymapEditorController.sizeFactor)
                case .decrement:
                    onAdjustSize(1 / KeymapEditorController.sizeFactor)
                @unknown default:
                    break
                }
            }
            .highPriorityGesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .named("keymapCanvas"))
                    .onChanged { value in
                        onChanged(value.location)
                    }
                    .onEnded { _ in
                        onEnded()
                    }
            )
    }
}

private struct EditorHandleChrome: View {
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: EditorHandleLayout.glyph, weight: .semibold))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(Color.white)
            .accessibilityHidden(true)
            .frame(width: EditorHandleLayout.side, height: EditorHandleLayout.side)
            .background(Circle().fill(KeycapChrome.fill))
            .overlay(Circle().stroke(Color.white.opacity(0.92), lineWidth: 1))
            .shadow(color: .black.opacity(0.35), radius: 1, y: 0.5)
    }
}

enum EditorHandleLayout {
    static let side: CGFloat = 16
    static let glyph: CGFloat = 8
    static let pad: CGFloat = 8
    /// Extra gap from the fill edge to the handle center, along x/y.
    static let outset: CGFloat = 2

    static func pull(box: CGSize, shape: KeymapButtonShape, scale: CGFloat) -> CGSize {
        let support = cornerSupport(box: box, shape: shape, scale: scale)
        let slack = pad - side / 2
        return CGSize(
            width: box.width / 2 + slack - support.width,
            height: box.height / 2 + slack - support.height
        )
    }

    static func resizeReference(title: String, shape: KeymapButtonShape) -> (width: Double, height: Double) {
        let unscaled = KeycapChrome.fittedSize(title: title, shape: shape, scale: 1)
        let support = cornerSupport(box: unscaled, shape: shape, scale: 1)
        return (Double(support.width * 2), Double(support.height * 2))
    }

    /// 1:1 resize so the bottom-right handle stays under the cursor.
    static func sizeAfterCornerResize(
        cursorX: Double,
        cursorY: Double,
        centerX: Double,
        centerY: Double,
        unscaledWidth: Double,
        unscaledHeight: Double,
        minScale: Double,
        maxScale: Double
    ) -> Double {
        let halfW = unscaledWidth / 2
        let halfH = unscaledHeight / 2
        let scaleX = halfW > 0 ? (cursorX - centerX) / halfW : minScale
        let scaleY = halfH > 0 ? (cursorY - centerY) / halfH : minScale
        let scale = min(max((scaleX + scaleY) / 2, minScale), maxScale)
        return NormalizedTransform.clampSize(NormalizedTransform.defaultSize * scale)
    }

    /// Support point from the box center toward the bottom-right fill.
    /// Circle uses a full radius; rectangle uses the drawn corner radius.
    private static func cornerSupport(box: CGSize, shape: KeymapButtonShape, scale: CGFloat) -> CGSize {
        let radius = min(chromeRadius(shape: shape, box: box, scale: scale), box.width / 2, box.height / 2)
        let inset = radius * (1 - 1 / sqrt(2))
        return CGSize(
            width: box.width / 2 - inset + outset,
            height: box.height / 2 - inset + outset
        )
    }

    private static func chromeRadius(shape: KeymapButtonShape, box: CGSize, scale: CGFloat) -> CGFloat {
        switch shape {
        case .circle: min(box.width, box.height) / 2
        case .rectangle: KeycapChrome.cornerRadius * scale
        }
    }
}
