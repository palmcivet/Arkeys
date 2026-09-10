import AppKit
import SwiftUI
import KeymapCore

struct KeymapKeycap: View {
    enum Style {
        case normal
        case selected
        case dimmed
        case overlay
        case overlayDimmed
    }

    let title: String
    let shape: KeymapButtonShape
    var style: Style = .normal
    var scale: CGFloat = 1

    var body: some View {
        let box = KeycapChrome.fittedSize(title: title, shape: shape, scale: scale)
        Text(title)
            .font(.system(size: KeycapChrome.fontSize * scale, weight: .regular))
            .foregroundStyle(.white)
            .lineLimit(1)
            .frame(width: box.width, height: box.height)
            .background(chrome)
            .shadow(color: .black.opacity(isOverlay ? 0.18 : 0.28), radius: 1.5, y: 1)
            .opacity(isOverlay ? 0.88 : 1)
    }

    private var isOverlay: Bool {
        style == .overlay || style == .overlayDimmed
    }

    private var fill: Color {
        switch style {
        case .selected: KeycapChrome.selectedFill
        case .dimmed, .overlayDimmed: KeycapChrome.dimmedFill
        case .normal, .overlay: KeycapChrome.fill
        }
    }

    private var lineWidth: CGFloat {
        style == .selected ? 1.5 : 1
    }

    @ViewBuilder
    private var chrome: some View {
        let stroke = style == .selected ? Color.white : Color.white.opacity(0.92)
        switch shape {
        case .circle:
            Circle()
                .fill(fill)
                .overlay(Circle().stroke(stroke, lineWidth: lineWidth))
        case .rectangle:
            RoundedRectangle(cornerRadius: KeycapChrome.cornerRadius * scale, style: .continuous)
                .fill(fill)
                .overlay(
                    RoundedRectangle(cornerRadius: KeycapChrome.cornerRadius * scale, style: .continuous)
                        .stroke(stroke, lineWidth: lineWidth)
                )
        }
    }
}

enum KeycapChrome {
    static let fontSize: CGFloat = 11
    static let minSide: CGFloat = 22
    static let maxSide: CGFloat = 144
    static let horizontalPadding: CGFloat = 7
    static let verticalPadding: CGFloat = 3
    static let cornerRadius: CGFloat = 1
    static let fill = Color(white: 0.22)
    static let selectedFill = Color(white: 0.32)
    static let dimmedFill = Color(white: 0.22).opacity(0.45)
    static let minScale: CGFloat = 1
    static let maxScale: CGFloat = min(
        maxSide / minSide,
        CGFloat(NormalizedTransform.maxSize / NormalizedTransform.defaultSize)
    )

    static func scale(for normalizedSize: Double) -> CGFloat {
        CGFloat(NormalizedTransform.visualScale(
            size: normalizedSize,
            minScale: Double(minScale),
            maxScale: Double(maxScale)
        ))
    }

    static func fittedSize(title: String, shape: KeymapButtonShape, scale: CGFloat) -> CGSize {
        let font = NSFont.systemFont(ofSize: fontSize * scale)
        let text = (title as NSString).size(withAttributes: [.font: font])
        switch shape {
        case .circle:
            let side = max(minSide * scale, ceil(text.width + horizontalPadding * 2 * scale))
            return CGSize(width: side, height: side)
        case .rectangle:
            return CGSize(
                width: max(minSide * scale, ceil(text.width + horizontalPadding * 2 * scale)),
                height: max(minSide * scale, ceil(text.height + verticalPadding * 2 * scale))
            )
        }
    }
}
