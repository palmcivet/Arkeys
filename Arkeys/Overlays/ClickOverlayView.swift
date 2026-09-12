import SwiftUI

struct ClickOverlayView: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.red.opacity(0.5))
                .frame(width: 20, height: 20)
            // strokeBorder draws inside the path so the ring is not clipped by the hosting view.
            Circle()
                .strokeBorder(Color.red, lineWidth: 2)
                .frame(width: 30, height: 30)
        }
        .frame(width: 50, height: 50)
        .accessibilityHidden(true)
    }
}

#Preview {
    ClickOverlayView()
}
