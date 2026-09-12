import AppKit
import SwiftUI
import InputRuntime
import KeymapCore

struct GeneralSettingsView: View {
    @EnvironmentObject private var runtime: InputRuntime

    var body: some View {
        Form {
            Section {
                Toggle("general.enabled", isOn: $runtime.isEnabled)
                Toggle("general.menuBarIcon", isOn: $runtime.showMenuBarIcon)
            } footer: {
                SettingsFooter("general.menuBarIcon.footer")
            }

            Section {
                Picker("keymap.buttonShape", selection: $runtime.keymapButtonShape) {
                    Text("keymap.buttonShape.circle").tag(KeymapButtonShape.circle)
                    Text("keymap.buttonShape.rectangle").tag(KeymapButtonShape.rectangle)
                }
                .pickerStyle(.segmented)
                Toggle("keymap.showOverlay", isOn: $runtime.showKeymapOverlay)
            } footer: {
                SettingsFooter("keymap.showOverlay.footer")
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
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
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
