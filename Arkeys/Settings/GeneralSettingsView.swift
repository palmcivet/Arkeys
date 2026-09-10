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
            } footer: {
                SettingsFooter("general.menuBarIcon.footer")
            }

            Section {
                LabeledContent("general.language") {
                    Text(currentLanguageDisplayName)
                        .foregroundStyle(.secondary)
                }
                Button("general.language.openSystemSettings") {
                    openSystemLanguageSettings()
                }
            } footer: {
                SettingsFooter("general.language.footer")
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

    /// Language currently resolved for this process (system or per-app override).
    private var currentLanguageDisplayName: String {
        let id = Bundle.main.preferredLocalizations.first ?? Locale.current.identifier
        let locale = Locale(identifier: id)
        if let code = locale.language.languageCode?.identifier,
           let name = locale.localizedString(forLanguageCode: code) {
            return name
        }
        return Locale.current.localizedString(forLanguageCode: id) ?? id
    }

    private func openSystemLanguageSettings() {
        // Language & Region in System Settings (macOS Ventura+).
        let candidates = [
            "x-apple.systempreferences:com.apple.Localization-Settings.extension",
            "x-apple.systempreferences:com.apple.Localization",
        ]
        for candidate in candidates {
            if let url = URL(string: candidate), NSWorkspace.shared.open(url) {
                return
            }
        }
    }
}
