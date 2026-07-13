import SwiftUI
import Injection
import InputRuntime

struct CompatibilitySettingsView: View {
    @EnvironmentObject private var runtime: InputRuntime

    var body: some View {
        Form {
            Section {
                Picker("compat.route", selection: $runtime.injectMode) {
                    ForEach(InjectMode.productCases) { mode in
                        Text(localizedName(for: mode))
                            .tag(mode)
                            .disabled(!isAvailable(mode))
                    }
                }
                .pickerStyle(.menu)
            } footer: {
                SettingsFooter("compat.route.footer")
            }

            Section {
                Button("compat.test") {
                    runtime.fireClick(relativeX: 0.5, relativeY: 0.5)
                }
                testResultLabel
            } footer: {
                SettingsFooter("compat.test.footer")
            }

            Section("compat.system") {
                LabeledContent("compat.system.os") {
                    Text(runtime.capability?.osVersion ?? "—")
                        .foregroundStyle(.secondary)
                }
                LabeledContent("compat.system.sandbox") {
                    Text(boolLabel(runtime.capability?.sandboxEnabled))
                        .foregroundStyle(.secondary)
                }
            }

            Section("compat.permissions") {
                LabeledContent("compat.permissions.ax") {
                    statusText(runtime.capability?.accessibilityTrusted)
                }
                LabeledContent("compat.permissions.tap") {
                    statusText(runtime.capability?.eventTapCreatable)
                }
                Button("compat.permissions.refresh") {
                    runtime.refreshCapability()
                }
            }

            Section("compat.api") {
                LabeledContent("compat.api.skylight") {
                    availabilityText(runtime.capability?.skyLightPostToPid)
                }
                LabeledContent("compat.api.authMessage") {
                    availabilityText(runtime.capability?.authMessage)
                }
            }

            Section {
                DisclosureGroup("compat.advanced") {
                    Toggle("compat.advanced.mouseMoved", isOn: $runtime.preferMouseMovedBeforeHID)
                    Toggle("compat.advanced.warp", isOn: $runtime.restoreCursorAfterHID)
                }
            }
        }
        .formStyle(.grouped)
        // Preference panes should fit without scrolling (Apple HIG for toolbar-style Settings).
        .scrollDisabled(true)
        .onChange(of: runtime.capability?.summaryLine) { _, _ in
            ensureSelectedModeAvailable()
        }
    }

    @ViewBuilder
    private var testResultLabel: some View {
        if runtime.lastInjectSummary.isEmpty {
            Text("compat.test.none")
                .foregroundStyle(.secondary)
        } else {
            Label {
                Text(runtime.lastInjectSummary)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            } icon: {
                Image(systemName: (runtime.lastInjectPosted ?? false) ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle((runtime.lastInjectPosted ?? false) ? .green : .red)
            }
        }
    }

    private func localizedName(for mode: InjectMode) -> String {
        switch mode {
        case .cascade: return String(localized: "inject.mode.cascade")
        case .postToPid: return String(localized: "inject.mode.postToPid")
        case .skyLight: return String(localized: "inject.mode.skyLight")
        case .hidTap: return String(localized: "inject.mode.hidTap")
        case .sessionTap: return mode.displayName
        }
    }

    private func isAvailable(_ mode: InjectMode) -> Bool {
        guard let report = runtime.capability else { return true }
        return mode.isAvailable(given: report)
    }

    private func ensureSelectedModeAvailable() {
        guard let report = runtime.capability else { return }
        if !runtime.injectMode.isAvailable(given: report) {
            runtime.injectMode = InjectMode.resolvedProductMode(raw: runtime.injectMode.rawValue, report: report)
        }
    }

    private func boolLabel(_ value: Bool?) -> String {
        guard let value else { return "—" }
        return String(localized: String.LocalizationValue(value ? "compat.on" : "compat.off"))
    }

    private func statusText(_ value: Bool?) -> some View {
        Text(boolLabel(value))
            .foregroundStyle(value == true ? .green : (value == false ? .orange : .secondary))
    }

    private func availabilityText(_ value: Bool?) -> some View {
        let text: String
        if let value {
            text = String(localized: String.LocalizationValue(value ? "compat.available" : "compat.unavailable"))
        } else {
            text = "—"
        }
        return Text(text)
            .foregroundStyle(value == true ? .green : (value == false ? .secondary : .secondary))
    }
}
