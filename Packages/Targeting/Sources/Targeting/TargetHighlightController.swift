import Foundation
import AppKit
import SwiftUI

/// Semi-transparent floating layer that follows a candidate target window while picking an app.
@MainActor
public final class TargetHighlightController: ObservableObject {
    @Published public private(set) var isVisible: Bool = false
    @Published public private(set) var previewBundleID: String?
    @Published public private(set) var statusText: String = ""

    private var overlayWindow: NSWindow?
    private var followTimer: Timer?

    public init() {}

    public func show(bundleID: String) {
        previewBundleID = bundleID
        isVisible = true
        ensureOverlay()
        startFollowing()
        overlayWindow?.orderFrontRegardless()
        syncOverlayFrame()
    }

    public func hide() {
        stopFollowing()
        overlayWindow?.orderOut(nil)
        previewBundleID = nil
        isVisible = false
        statusText = ""
    }

    private func ensureOverlay() {
        if overlayWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            window.isOpaque = false
            window.backgroundColor = .clear
            window.level = .floating
            window.ignoresMouseEvents = true
            window.hasShadow = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.contentView = NSHostingView(rootView: TargetHighlightOverlayView())
            overlayWindow = window
        }
    }

    private func startFollowing() {
        followTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.syncOverlayFrame()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        followTimer = timer
    }

    private func stopFollowing() {
        followTimer?.invalidate()
        followTimer = nil
    }

    private func syncOverlayFrame() {
        guard let previewBundleID,
              let app = RunningAppCatalog.runningApplication(bundleID: previewBundleID),
              let frame = TargetResolver.primaryWindowFrame(for: app) else {
            statusText = "Waiting for window…"
            return
        }
        statusText = app.localizedName ?? previewBundleID
        overlayWindow?.setFrame(frame, display: true)
    }
}

private struct TargetHighlightOverlayView: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 0)
                .fill(Color.cyan.opacity(0.22))
            RoundedRectangle(cornerRadius: 0)
                .strokeBorder(Color.cyan.opacity(0.85), lineWidth: 3)
            VStack {
                HStack {
                    Text("Target Preview")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 6))
                        .padding(12)
                    Spacer()
                }
                Spacer()
            }
        }
    }
}
