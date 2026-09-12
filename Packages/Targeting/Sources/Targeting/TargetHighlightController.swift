import Foundation
import AppKit
import SwiftUI

/// Host-supplied overlay copy. Targeting does not read the app catalog.
public struct TargetHighlightCopy: Equatable, Sendable {
    public var waitingStatus: String
    public var targetPreview: String

    public init(waitingStatus: String, targetPreview: String) {
        self.waitingStatus = waitingStatus
        self.targetPreview = targetPreview
    }

    public static let english = TargetHighlightCopy(
        waitingStatus: "Waiting for window…",
        targetPreview: "Target Preview"
    )
}

/// Semi-transparent floating layer that follows a candidate target window while picking an app.
@MainActor
public final class TargetHighlightController: ObservableObject {
    @Published public private(set) var isVisible: Bool = false
    @Published public private(set) var previewBundleID: String?
    @Published public private(set) var statusText: String = ""
    public var copy: TargetHighlightCopy

    private var overlayWindow: NSWindow?
    private var followTimer: Timer?

    public init(copy: TargetHighlightCopy = .english) {
        self.copy = copy
    }

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
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            window.contentView = NSHostingView(rootView: TargetHighlightOverlayView(copy: copy))
            window.hideFromAccessibility()
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
            statusText = copy.waitingStatus
            return
        }
        statusText = app.localizedName ?? previewBundleID
        overlayWindow?.setFrame(frame, display: true)
    }
}

private struct TargetHighlightOverlayView: View {
    var copy: TargetHighlightCopy
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let fillOpacity = reduceTransparency ? 0.42 : 0.22
        let badgeOpacity = reduceTransparency ? 0.88 : 0.55
        let strokeWidth: CGFloat = contrast == .increased ? 4 : 3
        ZStack {
            RoundedRectangle(cornerRadius: 0)
                .fill(Color.cyan.opacity(fillOpacity))
            RoundedRectangle(cornerRadius: 0)
                .strokeBorder(Color.cyan.opacity(0.85), lineWidth: strokeWidth)
            VStack {
                HStack {
                    Text(copy.targetPreview)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.black.opacity(badgeOpacity), in: RoundedRectangle(cornerRadius: 6))
                        .padding(12)
                    Spacer()
                }
                Spacer()
            }
        }
        .accessibilityHidden(true)
    }
}
