import SwiftUI

struct ContentView: View {
    @EnvironmentObject var inputMonitor: InputMonitor

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Striker Settings")
                    .font(.title2)

                Group {
                    labeledField("Click hotkey", text: $inputMonitor.hotkey)
                    labeledField("Escape hotkey", text: $inputMonitor.escapeHotkey)

                    HStack {
                        Text("Click X (from window top-left)")
                        TextField("100", value: $inputMonitor.clickX, formatter: NumberFormatter())
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                    }

                    HStack {
                        Text("Click Y (from window top-left)")
                        TextField("100", value: $inputMonitor.clickY, formatter: NumberFormatter())
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                    }
                }

                Divider()

                Text("Inject path")
                    .font(.headline)

                Picker("Mode", selection: $inputMonitor.injectMode) {
                    ForEach(InjectMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.menu)

                Toggle("HID: prepend mouseMoved", isOn: $inputMonitor.preferMouseMovedBeforeHID)
                Toggle("HID/session: warp cursor back", isOn: $inputMonitor.restoreCursorAfterHID)

                HStack(spacing: 12) {
                    Button("Fire Click") { inputMonitor.fireClick() }
                        .keyboardShortcut(.defaultAction)
                    Button("Fire Escape") { inputMonitor.fireEscape() }
                    Button("Re-probe") { inputMonitor.refreshCapability() }
                }

                Divider()

                Text("Listening: \(inputMonitor.isListening ? "YES (global)" : "NO — grant Accessibility & relaunch")")
                    .foregroundStyle(inputMonitor.isListening ? .green : .red)

                Text("Capability")
                    .font(.headline)
                Text(inputMonitor.capabilitySummary.isEmpty ? "(probing…)" : inputMonitor.capabilitySummary)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)

                Text("Last inject")
                    .font(.headline)
                Text(inputMonitor.lastInjectSummary)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)

                Text("Grant Accessibility in System Settings → Privacy & Security. Watch Xcode console for [Striker] logs.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .frame(minWidth: 420, minHeight: 420)
    }

    @ViewBuilder
    private func labeledField(_ title: String, text: Binding<String>) -> some View {
        HStack {
            Text(title)
            TextField("", text: text)
                .textFieldStyle(.roundedBorder)
                .frame(width: 80)
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(InputMonitor())
}
