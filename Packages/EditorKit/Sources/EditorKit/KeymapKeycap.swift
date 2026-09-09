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

    var body: some View {
        Text(title)
            .font(.system(size: KeycapChrome.fontSize, weight: .regular))
            .foregroundStyle(.white)
            .minimumScaleFactor(0.6)
            .lineLimit(1)
            .padding(.horizontal, shape == .rectangle ? KeycapChrome.horizontalPadding : 0)
            .padding(.vertical, shape == .rectangle ? KeycapChrome.verticalPadding : 0)
            .frame(minWidth: KeycapChrome.minSide, minHeight: KeycapChrome.minSide)
            .frame(
                width: shape == .circle ? KeycapChrome.minSide : nil,
                height: shape == .circle ? KeycapChrome.minSide : nil
            )
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
