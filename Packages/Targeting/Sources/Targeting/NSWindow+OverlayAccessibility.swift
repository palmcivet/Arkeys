import AppKit

public extension NSWindow {
    /// Click-through / decorative overlays must not appear in VoiceOver.
    func hideFromAccessibility() {
        setAccessibilityElement(false)
        contentView?.setAccessibilityElement(false)
    }
}
