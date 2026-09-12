import SwiftUI
import Injection
import InputRuntime

struct CompatibilitySettingsView: View {
    @EnvironmentObject private var runtime: InputRuntime
    @State private var settingsOpenFailed = false

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
                Toggle("compat.hid.mouseMoved", isOn: $runtime.preferMouseMovedBeforeHID)
                Toggle("compat.hid.restoreCursor", isOn: $runtime.restoreCursorAfterHID)
            } footer: {
                SettingsFooter("compat.hid.footer")
            }
            .disabled(runtime.injectMode != .hidTap && runtime.injectMode != .cascade)

            Section {
                LabeledContent("compat.status.accessibility") {
                    statusText(runtime.capability?.accessibilityTrusted)
                }
                LabeledContent("compat.status.eventTap") {
                    statusText(runtime.capability?.eventTapCreatable)
                }
                LabeledContent("compat.status.skyLight") {
                    availabilityText(runtime.capability?.skyLightPostToPid)
                }
                LabeledContent("compat.status.authMessage") {
                    availabilityText(runtime.capability?.authMessage)
                }
                LabeledContent("compat.status.macos") {
                    Text(runtime.capability?.osVersion ?? "—")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Button("compat.status.grantPermission") {
                        if !runtime.openAccessibilitySettings() {
                            settingsOpenFailed = true
                        }
                    }
                    .disabled(runtime.capability?.accessibilityTrusted == true)
                    Button("compat.status.refresh") {
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
        .systemSettingsOpenFailedAlert(
            isPresented: $settingsOpenFailed,
            message: "compat.status.grantPermission.failed"
        )
    }

    @ViewBuilder
    private var testResultLabel: some View {
        if runtime.lastInjectSummary.isEmpty {
            Text("compat.test.none")
                .foregroundStyle(.secondary)
                .settingsMultilineLeading()
        } else {
            Label {
                Text(runtime.lastInjectSummary)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .settingsMultilineLeading()
                    .textSelection(.enabled)
            } icon: {
                Image(systemName: (runtime.lastInjectPosted ?? false) ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle((runtime.lastInjectPosted ?? false) ? .green : .red)
                    .accessibilityHidden(true)
            }
        }
    }

    private func localizedName(for mode: InjectMode) -> String {
        switch mode {
        case .cascade: return String(localized: "compat.route.automatic")
        case .postToPid: return String(localized: "compat.route.postToProcess")
        case .skyLight: return String(localized: "compat.route.skyLight")
        case .hidTap: return String(localized: "compat.route.globalHID")
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
        return value
            ? String(localized: "compat.status.on")
            : String(localized: "compat.status.off")
    }

    private func statusText(_ value: Bool?) -> some View {
        labeledStatus(
            boolLabel(value),
            value: value,
            on: .green,
            off: .orange,
            onSymbol: "checkmark.circle.fill",
            offSymbol: "xmark.circle.fill"
        )
    }

    private func availabilityText(_ value: Bool?) -> some View {
        let text: String
        if let value {
            text = value
                ? String(localized: "compat.status.available")
                : String(localized: "compat.status.unavailable")
        } else {
            text = "—"
        }
        return labeledStatus(
            text,
            value: value,
            on: .green,
            off: .secondary,
            onSymbol: "checkmark.circle.fill",
            offSymbol: "minus.circle.fill"
        )
    }

    private func labeledStatus(
        _ text: String,
        value: Bool?,
        on: Color,
        off: Color,
        onSymbol: String,
        offSymbol: String
    ) -> some View {
        HStack(spacing: 4) {
            if let value {
                Image(systemName: value ? onSymbol : offSymbol)
                    .foregroundStyle(value ? on : off)
                    .accessibilityHidden(true)
            }
            // Words carry the status; color on the icon is supplementary.
            Text(text)
                .foregroundStyle(.secondary)
        }
    }
}
