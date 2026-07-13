import AppKit
import SwiftUI
import InputRuntime
import Targeting

struct GeneralSettingsView: View {
    @EnvironmentObject private var runtime: InputRuntime
    @StateObject private var highlight = TargetHighlightController()
    @State private var isPickingApp = false

    var body: some View {
        Form {
            Section {
                Toggle("general.enabled", isOn: $runtime.isEnabled)
                Toggle("general.menuBarIcon", isOn: $runtime.showMenuBarIcon)
            }

            Section {
                LabeledContent("general.target") {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(runtime.targetBundleID == nil
                             ? String(localized: "general.target.none")
                             : runtime.targetAppName)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        if let bundleID = runtime.targetBundleID {
                            Text(bundleID)
                                .font(.system(size: NSFont.smallSystemFontSize, design: .monospaced))
                                .foregroundStyle(.tertiary)
                                .textSelection(.enabled)
                                .lineLimit(1)
                        }
                    }
                }

                Button("general.target.choose") {
                    isPickingApp = true
                }
            } footer: {
                SettingsFooter("general.target.footer")
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .sheet(isPresented: $isPickingApp, onDismiss: {
            highlight.hide()
        }) {
            AppPickerSheet(
                apps: runtime.selectableApps(),
                currentBundleID: runtime.targetBundleID,
                highlight: highlight
            ) { app in
                runtime.bind(bundleID: app.bundleIdentifier, appName: app.name)
                isPickingApp = false
                highlight.hide()
            }
        }
    }
}
