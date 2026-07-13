import SwiftUI

struct ClickOverlayView: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.red.opacity(0.5))
                .frame(width: 20, height: 20)
            Circle()
                .stroke(Color.red, lineWidth: 2)
                .frame(width: 30, height: 30)
        }
    }
}

#Preview {
    ClickOverlayView()
}
