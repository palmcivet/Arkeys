import AppKit
import SwiftUI
import InputRuntime
import KeymapCore

struct GeneralSettingsView: View {
    @EnvironmentObject private var runtime: InputRuntime
    @State private var settingsOpenFailed = false

    var body: some View {
        Form {
            Section {
                Toggle("general.enabled", isOn: $runtime.isEnabled)
                Toggle("general.menuBarIcon", isOn: $runtime.showMenuBarIcon)
            } footer: {
                SettingsFooter("general.menuBarIcon.footer")
            }

            Section {
                Toggle("general.showShortcuts", isOn: $runtime.showKeymapOverlay)
                LabeledContent {
                    VStack(spacing: 1) {
                        OverlayOpacitySlider(value: $runtime.keymapOverlayOpacity)
                            .frame(
                                width: GeneralSettingsMetrics.trailingControlWidth,
                                height: OverlayOpacityControl.sliderHeight
                            )
                        OverlayOpacityCaptions()
                    }
                    .alignmentGuide(VerticalAlignment.center) { _ in
                        OverlayOpacityControl.trackCenterY
                    }
                } label: {
                    Text("general.shortcutOpacity")
                        .accessibilityHidden(true)
                }
                .disabled(!runtime.showKeymapOverlay)
                LabeledContent("general.shortcutShape") {
                    Picker("general.shortcutShape", selection: $runtime.keymapButtonShape) {
                        Text("general.shortcutShape.circle").tag(KeymapButtonShape.circle)
                        Text("general.shortcutShape.rectangle").tag(KeymapButtonShape.rectangle)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: GeneralSettingsMetrics.trailingControlWidth)
                }
            }

            Section {
                LabeledContent("general.language") {
                    Text(currentLanguageDisplayName)
                        .foregroundStyle(.secondary)
                }
                Button("general.language.openSystemSettings") {
                    if !openSystemLanguageSettings() {
                        settingsOpenFailed = true
                    }
                }
            } footer: {
                SettingsFooter("general.language.footer")
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .systemSettingsOpenFailedAlert(
            isPresented: $settingsOpenFailed,
            message: "general.language.openFailed"
        )
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

    private func openSystemLanguageSettings() -> Bool {
        // Language & Region in System Settings (macOS Ventura+).
        SystemSettingsOpener.open([
            "x-apple.systempreferences:com.apple.Localization-Settings.extension",
            "x-apple.systempreferences:com.apple.Localization",
        ])
    }
}

private enum GeneralSettingsMetrics {
    static let trailingControlWidth: CGFloat = 216
}

/// Tracking Speed–style slider: ticks on the rail as reference, a few captions
/// under the ends/midpoint. `trackCenterY` keeps the Form label on the rail.
private enum OverlayOpacityControl {
    static let tickCount = 7
    static let sliderHeight: CGFloat = 28
    static let trackCenterY: CGFloat = 10
    static let trackInset: CGFloat = 10

    static func normalized(_ value: Double) -> Double {
        let min = AppSettings.keymapOverlayOpacityMinimum
        let max = AppSettings.keymapOverlayOpacityMaximum
        let span = max - min
        guard span > 0 else { return 1 }
        return (AppSettings.clampedKeymapOverlayOpacity(value) - min) / span
    }
}

private struct OverlayOpacitySlider: NSViewRepresentable {
    @Binding var value: Double

    func makeCoordinator() -> OverlayOpacitySliderCoordinator {
        OverlayOpacitySliderCoordinator(value: $value)
    }

    func makeNSView(context: Context) -> OverlayOpacityNSSlider {
        let slider = OverlayOpacityNSSlider()
        slider.minValue = AppSettings.keymapOverlayOpacityMinimum
        slider.maxValue = AppSettings.keymapOverlayOpacityMaximum
        slider.doubleValue = value
        slider.numberOfTickMarks = OverlayOpacityControl.tickCount
        slider.tickMarkPosition = .below
        slider.allowsTickMarkValuesOnly = false
        slider.controlSize = .regular
        slider.isContinuous = true
        slider.target = context.coordinator
        slider.action = #selector(OverlayOpacitySliderCoordinator.valueChanged(_:))
        return slider
    }

    func updateNSView(_ slider: OverlayOpacityNSSlider, context: Context) {
        context.coordinator.value = $value
        if abs(slider.doubleValue - value) > 0.0001 {
            slider.doubleValue = value
        }
        slider.isEnabled = context.environment.isEnabled
    }
}

/// File-level so AppKit target-action is not isolated through a SwiftUI `View`.
private final class OverlayOpacitySliderCoordinator: NSObject {
    var value: Binding<Double>

    init(value: Binding<Double>) {
        self.value = value
    }

    @objc func valueChanged(_ sender: NSSlider) {
        value.wrappedValue = sender.doubleValue
    }
}

/// Slider owns the AX name/value so VoiceOver does not also read the Form label.
private final class OverlayOpacityNSSlider: NSSlider {
    override func accessibilityLabel() -> String? {
        String(localized: "general.shortcutOpacity")
    }

    override func accessibilityValue() -> Any? {
        OverlayOpacityControl.normalized(doubleValue)
            .formatted(.percent.precision(.fractionLength(0)))
    }
}

private struct OverlayOpacityCaptions: View {
    var body: some View {
        HStack {
            Text("general.shortcutOpacity.faint")
            Spacer()
            Text("general.shortcutOpacity.medium")
            Spacer()
            Text("general.shortcutOpacity.solid")
        }
        .font(.system(size: NSFont.smallSystemFontSize))
        .foregroundStyle(.secondary)
        .padding(.horizontal, OverlayOpacityControl.trackInset)
        .frame(width: GeneralSettingsMetrics.trailingControlWidth)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
