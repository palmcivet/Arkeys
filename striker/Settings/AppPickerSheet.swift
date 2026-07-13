import SwiftUI
import Targeting

struct AppPickerSheet: View {
    let apps: [SelectableApp]
    let currentBundleID: String?
    @ObservedObject var highlight: TargetHighlightController
    let onSelect: (SelectableApp) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selected: SelectableApp?
    @State private var query = ""

    private var filtered: [SelectableApp] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return apps }
        return apps.filter {
            $0.name.localizedCaseInsensitiveContains(q)
                || $0.bundleIdentifier.localizedCaseInsensitiveContains(q)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("picker.title")
                .font(.title3.weight(.semibold))
            Text("picker.footer")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("picker.search", text: $query)
                .textFieldStyle(.roundedBorder)

            List(filtered, selection: Binding(
                get: { selected?.id },
                set: { newID in
                    selected = filtered.first { $0.id == newID }
                    if let selected {
                        highlight.show(bundleID: selected.bundleIdentifier)
                    }
                }
            )) { app in
                HStack(spacing: 10) {
                    if let icon = RunningAppCatalog.icon(forBundleID: app.bundleIdentifier) {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 28, height: 28)
                    } else {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.secondary.opacity(0.2))
                            .frame(width: 28, height: 28)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(app.name)
                            if app.bundleIdentifier == currentBundleID {
                                Text("picker.current")
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.accentColor.opacity(0.2), in: Capsule())
                            }
                        }
                        Text(app.bundleIdentifier)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .tag(app.id)
                .contentShape(Rectangle())
                .onTapGesture {
                    selected = app
                    highlight.show(bundleID: app.bundleIdentifier)
                }
            }
            .frame(minHeight: 280)

            if !highlight.statusText.isEmpty {
                Text(String(localized: "picker.preview \(highlight.statusText)"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("picker.cancel") {
                    highlight.hide()
                    dismiss()
                }
                Spacer()
                Button("picker.bind") {
                    if let selected {
                        onSelect(selected)
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selected == nil)
            }
        }
        .padding(20)
        .frame(width: 460, height: 520)
        .onDisappear {
            highlight.hide()
        }
    }
}
