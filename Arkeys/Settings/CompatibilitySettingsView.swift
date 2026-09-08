import SwiftUI
import Injection
import InputRuntime

struct CompatibilitySettingsView: View {
    @EnvironmentObject private var runtime: InputRuntime

    var body: some View {
        Form {
            Section {
                // Menu (not Picker.menu): macOS menu pickers omit `.disabled` options;
                // Menu buttons stay visible and gray out when unavailable.
                LabeledContent("compat.route") {
                    Menu {
                        ForEach(InjectMode.productCases) { mode in
                            Button {
                                runtime.injectMode = mode
                            } label: {
                                if runtime.injectMode == mode {
                                    Label(localizedName(for: mode), systemImage: "checkmark")
                                } else {
                                    Text(localizedName(for: mode))
                                }
                            }
                            .disabled(!isAvailable(mode))
                        }
                    } label: {
                        Text(localizedName(for: runtime.injectMode))
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
            } footer: {
                SettingsFooter("compat.route.footer")
            }

            Section {
                Toggle("compat.advanced.mouseMoved", isOn: $runtime.preferMouseMovedBeforeHID)
                Toggle("compat.advanced.warp", isOn: $runtime.restoreCursorAfterHID)
            } footer: {
                SettingsFooter("compat.hid.footer")
            }
            .disabled(runtime.injectMode != .hidTap && runtime.injectMode != .cascade)

            Section {
                LabeledContent("compat.permissions.ax") {
                    statusText(runtime.capability?.accessibilityTrusted)
                }
                LabeledContent("compat.permissions.tap") {
                    statusText(runtime.capability?.eventTapCreatable)
                }
                LabeledContent("compat.api.skylight") {
                    availabilityText(runtime.capability?.skyLightPostToPid)
                }
                LabeledContent("compat.api.authMessage") {
                    availabilityText(runtime.capability?.authMessage)
                }
                LabeledContent("compat.system.os") {
                    Text(runtime.capability?.osVersion ?? "—")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Button("compat.permissions.grantPermission") {
                        runtime.openAccessibilitySettings()
                    }
                    .disabled(runtime.capability?.accessibilityTrusted == true)
                    Button("compat.permissions.refresh") {
                        runtime.refreshCapability()
                    }
                }
            }

            Section {
                Button("compat.test") {
                    runtime.fireTestClick(relativeX: 0.5, relativeY: 0.5)
                }
                testResultLabel
            } footer: {
                SettingsFooter("compat.test.footer")
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
