import AppKit
import SwiftUI

/// Preference-pane description text.
///
/// Apple’s macOS settings convention (and classic HIG practice): place help copy
/// directly under the related controls at **Small / 11pt** with **secondary label** color.
/// SwiftUI `Form` section footers do not reliably apply this on macOS the way iOS Settings does,
/// so we style explicitly.
struct SettingsFooter: View {
    private let key: LocalizedStringKey

    init(_ key: LocalizedStringKey) {
        self.key = key
    }

    var body: some View {
        Text(key)
            .font(.system(size: NSFont.smallSystemFontSize))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
