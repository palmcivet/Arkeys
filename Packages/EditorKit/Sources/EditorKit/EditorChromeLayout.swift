import Foundation
import KeymapCore

enum EditorChromeEdge: Equatable {
    case top
    case bottom
}

/// Host-supplied chrome and VoiceOver copy. EditorKit does not read the app catalog.
public struct EditorChromeCopy: Equatable, Sendable {
    public var cancel: String
    public var done: String
    public var idleStatus: String
    public var waitingStatus: String
    public var selectButtonFirst: String
    public var boundFormat: String
    public var deleted: String
    public var selectedFormat: String
    public var deleteKey: String
    public var resizeKey: String
    public var deleteHelp: String
    public var resizeHelp: String
    public var resizeHint: String
    public var keyHint: String
    public var addKey: String
    public var moveLeft: String
    public var moveRight: String
    public var moveUp: String
    public var moveDown: String

    public init(
        cancel: String,
        done: String,
        idleStatus: String,
        waitingStatus: String,
        selectButtonFirst: String,
        boundFormat: String,
        deleted: String,
        selectedFormat: String,
        deleteKey: String,
        resizeKey: String,
        deleteHelp: String,
        resizeHelp: String,
        resizeHint: String,
        keyHint: String,
        addKey: String,
        moveLeft: String,
        moveRight: String,
        moveUp: String,
        moveDown: String
    ) {
        self.cancel = cancel
        self.done = done
        self.idleStatus = idleStatus
        self.waitingStatus = waitingStatus
        self.selectButtonFirst = selectButtonFirst
        self.boundFormat = boundFormat
        self.deleted = deleted
        self.selectedFormat = selectedFormat
        self.deleteKey = deleteKey
        self.resizeKey = resizeKey
        self.deleteHelp = deleteHelp
        self.resizeHelp = resizeHelp
        self.resizeHint = resizeHint
        self.keyHint = keyHint
        self.addKey = addKey
        self.moveLeft = moveLeft
        self.moveRight = moveRight
        self.moveUp = moveUp
        self.moveDown = moveDown
    }

    public static let english = EditorChromeCopy(
        cancel: "Cancel",
        done: "Done",
        idleStatus: "Click empty area to add",
        waitingStatus: "Waiting for target window…",
        selectButtonFirst: "Select a button first, then press a key",
        boundFormat: "Bound %@ — press a key · drag · × to delete",
        deleted: "Deleted",
        selectedFormat: "Selected %@ — press a key · drag · × to delete",
        deleteKey: "Delete key",
        resizeKey: "Resize key",
        deleteHelp: "Delete",
        resizeHelp: "Resize",
        resizeHint: "Drag or adjust to resize",
        keyHint: "Press a key to bind. Drag or use actions to move.",
        addKey: "Add key at center",
        moveLeft: "Move left",
        moveRight: "Move right",
        moveUp: "Move up",
        moveDown: "Move down"
    )

    public func boundStatus(name: String) -> String {
        String(format: boundFormat, locale: .current, arguments: [name])
    }

    public func selectedStatus(name: String) -> String {
        String(format: selectedFormat, locale: .current, arguments: [name])
    }
}

/// In-canvas HUD dodge: stay put until the selected or dragged keycap enters
/// the current bar's zone, then flip. A key already on the other side does not
/// block. Leaving the zone does not return the bar. Pointer is ignored so
/// buttons stay clickable.
enum EditorChromeDodge {
    static let margin: CGFloat = 48
    static let horizontalInset: CGFloat = 12
    static let islandHeight: CGFloat = 36
    static let approach: CGFloat = 28
    /// Comfortable default when status + buttons fit.
    static let barMinWidth: CGFloat = 400
    /// Hard cap; also never exceed the target canvas.
    static let barMaxWidth: CGFloat = 620
    static let estimatedBarSize = CGSize(width: barMinWidth, height: islandHeight)

    static func availableWidth(canvasWidth: CGFloat) -> CGFloat {
        max(canvasWidth - horizontalInset * 2, 1)
    }

    /// 400 when content fits; otherwise hug content, capped at min(620, canvas).
    static func fittedBarWidth(canvasWidth: CGFloat, contentWidth: CGFloat = 0) -> CGFloat {
        let available = availableWidth(canvasWidth: canvasWidth)
        let desired = max(contentWidth, barMinWidth)
        return min(desired, barMaxWidth, available)
    }

    static func barFrame(
        edge: EditorChromeEdge,
        canvas: CGSize,
        barSize: CGSize,
        margin: CGFloat = margin
    ) -> CGRect {
        let width = min(max(barSize.width, 1), availableWidth(canvasWidth: canvas.width))
        let height = max(barSize.height, 1)
        let x = (canvas.width - width) / 2
        let y: CGFloat = switch edge {
        case .top: margin
        case .bottom: canvas.height - margin - height
        }
        return CGRect(x: x, y: y, width: width, height: height)
    }

    static func barCenterY(
        edge: EditorChromeEdge,
        canvas: CGSize,
        barHeight: CGFloat,
        margin: CGFloat = margin
    ) -> CGFloat {
        switch edge {
        case .top: margin + barHeight / 2
        case .bottom: canvas.height - margin - barHeight / 2
        }
    }

    static func keycapFrame(
        centerX: CGFloat,
        centerY: CGFloat,
        title: String,
        shape: KeymapButtonShape,
        scale: CGFloat
    ) -> CGRect {
        let size = KeycapChrome.fittedSize(title: title, shape: shape, scale: scale)
        return CGRect(
            x: centerX - size.width / 2,
            y: centerY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    static func resolve(
        current: EditorChromeEdge,
        canvas: CGSize,
        barSize: CGSize,
        obstacles: [CGRect]
    ) -> EditorChromeEdge {
        guard canvas.width > 0, canvas.height > 0 else { return current }
        let other: EditorChromeEdge = current == .bottom ? .top : .bottom
        let currentHit = isThreatened(
            edge: current,
            padding: approach,
            canvas: canvas,
            barSize: barSize,
            obstacles: obstacles
        )
        guard currentHit else { return current }
        return other
    }

    private static func isThreatened(
        edge: EditorChromeEdge,
        padding: CGFloat,
        canvas: CGSize,
        barSize: CGSize,
        obstacles: [CGRect]
    ) -> Bool {
        let zone = barFrame(edge: edge, canvas: canvas, barSize: barSize)
            .insetBy(dx: -padding, dy: -padding)
        return obstacles.contains { obstacle in
            obstacle.intersects(zone)
        }
    }
}

enum EditorOverlayDecision: Equatable {
    case hide
    case show
    case showAndReturnFocus
}

/// Whether the floating editor mask should be up while some other app,
/// Arkeys itself, or the target is frontmost.
enum EditorOverlayPolicy {
    static func decide(
        targetIsFrontmost: Bool,
        hostIsFrontmost: Bool,
        hideForHostUI: Bool,
        statusMenuTracking: Bool,
        overlayInteraction: Bool
    ) -> EditorOverlayDecision {
        if targetIsFrontmost {
            return .show
        }
        if !hostIsFrontmost {
            return .hide
        }
        if statusMenuTracking {
            return .show
        }
        if hideForHostUI {
            return .hide
        }
        if overlayInteraction {
            return .showAndReturnFocus
        }
        return .hide
    }
}
