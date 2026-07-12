import SwiftUI
import UniformTypeIdentifiers
import KeymapCore
import KeymapPlayCover
import Injection
import InputRuntime
import EditorKit
import Targeting

struct ContentView: View {
    @EnvironmentObject var runtime: InputRuntime
    @StateObject private var editor = KeymapEditorController()
    @StateObject private var highlight = TargetHighlightController()
    @State private var importError: String?
    @State private var isImporting = false
    @State private var isPickingApp = false
    @State private var statusMessage: String?

    private let registry = KeymapSchemeRegistry(parserTypes: [PlayCoverKeymapParser.self])

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Striker Settings")
                    .font(.title2)

                Group {
                    Toggle("Enabled", isOn: $runtime.isEnabled)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Target（目标应用）")
                            .font(.headline)
                        Text("仅当该应用在前台时，键位才会生效。")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        HStack {
                            Text(runtime.targetAppName)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Spacer()
                            Button("选择应用…") {
                                isPickingApp = true
                            }
                        }

                        Text(runtime.targetBundleID ?? "(no bundle id)")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }

                    Text("Keymap（键鼠方案）")
                        .font(.headline)

                    if runtime.targetBundleID == nil {
                        Text("请先选择目标应用，再导入或新建方案。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if runtime.schemes.isEmpty {
                        Text("尚无方案 — 可新建或导入。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("当前方案", selection: Binding(
                            get: { runtime.activeSchemeID },
                            set: { newID in
                                if let newID {
                                    runtime.selectScheme(id: newID)
                                }
                            }
                        )) {
                            ForEach(runtime.schemes) { scheme in
                                Text(scheme.name).tag(Optional(scheme.id))
                            }
                        }
                        .pickerStyle(.menu)
                        .disabled(editor.isActive)
                    }

                    Text(runtime.keymapSummary)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)

                    HStack {
                        Button("新建方案") { createNewScheme() }
                            .disabled(runtime.targetBundleID == nil || editor.isActive)
                            .help("为目标应用创建空白键位图，并进入 overlay 编辑")
                        Button("编辑方案") { beginEdit() }
                            .disabled(runtime.activeSchemeID == nil || editor.isActive)
                        Button("导入 PlayCover…") { isImporting = true }
                            .disabled(runtime.targetBundleID == nil || editor.isActive)
                        Button("删除方案") { deleteActiveScheme() }
                            .disabled(runtime.activeSchemeID == nil || editor.isActive)
                    }

                    if let importError {
                        Text(importError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    if let statusMessage {
                        Text(statusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text("Future schemes: MuMu / LDPlayer (parser interface reserved)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Divider()

                Text("Inject path")
                    .font(.headline)

                Picker("Mode", selection: $runtime.injectMode) {
                    ForEach(InjectMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.menu)

                Toggle("HID: prepend mouseMoved", isOn: $runtime.preferMouseMovedBeforeHID)
                Toggle("HID/session: warp cursor back", isOn: $runtime.restoreCursorAfterHID)

                HStack(spacing: 12) {
                    Button("Fire Click (center)") {
                        runtime.fireClick(relativeX: 0.5, relativeY: 0.5)
                    }
                    Button("Fire Escape") { runtime.fireEscape() }
                    Button("Re-probe") { runtime.refreshCapability() }
                }

                Divider()

                Text("Listening: \(runtime.isListening ? "YES (global)" : "NO — grant Accessibility & relaunch")")
                    .foregroundStyle(runtime.isListening ? .green : .red)

                Text("Editing: \(editor.isActive ? "YES" : "no")")
                    .foregroundStyle(editor.isActive ? .orange : .secondary)

                Text("Capability")
                    .font(.headline)
                Text(runtime.capabilitySummary.isEmpty ? "(probing…)" : runtime.capabilitySummary)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)

                Text("Last inject")
                    .font(.headline)
                Text(runtime.lastInjectSummary)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)

                Text("Grant Accessibility in System Settings. Import a PlayCover .plist/.playmap or create/edit overlay bindings on the target window.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .frame(width: 460)
        .frame(minHeight: 520)
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.propertyList, .data],
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }
        .sheet(isPresented: $isPickingApp, onDismiss: {
            highlight.hide()
        }) {
            AppPickerSheet(
                apps: runtime.selectableApps(),
                currentBundleID: runtime.targetBundleID,
                highlight: highlight
            ) { app in
                runtime.bind(bundleID: app.bundleIdentifier, appName: app.name)
                statusMessage = "已选择目标：\(app.name)"
                isPickingApp = false
                highlight.hide()
            }
        }
        .onAppear {
            wireEditorCallbacks()
        }
    }

    private func wireEditorCallbacks() {
        editor.onFinished = { map in
            runtime.keymap = map
            runtime.saveKeymap()
            runtime.isEditing = false
            runtime.onEditorKeyDown = nil
            statusMessage = "方案已保存"
        }
        editor.onCancelled = {
            runtime.isEditing = false
            runtime.onEditorKeyDown = nil
        }
    }

    private func createNewScheme() {
        let name = nextUntitledSchemeName()
        guard runtime.createNewKeymap(name: name) else {
            statusMessage = "请先选择目标应用"
            return
        }
        statusMessage = "已新建：\(name)"
        beginEdit()
    }

    private func deleteActiveScheme() {
        let name = runtime.schemes.first(where: { $0.id == runtime.activeSchemeID })?.name ?? "方案"
        runtime.deleteActiveScheme()
        statusMessage = "已删除：\(name)"
    }

    private func beginEdit() {
        guard let bundleID = runtime.targetBundleID, runtime.activeSchemeID != nil else { return }
        wireEditorCallbacks()
        runtime.isEditing = true
        runtime.onEditorKeyDown = { [weak editor] code, name in
            editor?.bindKey(keyCode: code, name: name)
        }
        editor.start(targetBundleID: bundleID, keymap: runtime.keymap)
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        importError = nil
        do {
            let urls = try result.get()
            guard let url = urls.first else { return }
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            let map = try registry.importKeymap(data: data, filename: url.lastPathComponent)
            let suggested = url.deletingPathExtension().lastPathComponent
            runtime.applyImportedKeymap(map, suggestedName: suggested)
            statusMessage = "已导入：\(suggested)"
        } catch {
            importError = error.localizedDescription
        }
    }

    private func nextUntitledSchemeName() -> String {
        let base = "未命名方案"
        let existing = Set(runtime.schemes.map(\.name))
        guard existing.contains(base) else { return base }
        var index = 2
        while existing.contains("\(base) \(index)") {
            index += 1
        }
        return "\(base) \(index)"
    }
}

private struct AppPickerSheet: View {
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
            Text("选择目标应用")
                .font(.title3.weight(.semibold))
            Text("点击列表项时，目标窗口会显示半透明浮层以便确认。")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("搜索名称或 bundle id", text: $query)
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
                                Text("当前")
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
                Text("预览：\(highlight.statusText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("取消") {
                    highlight.hide()
                    dismiss()
                }
                Spacer()
                Button("绑定所选") {
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

#Preview {
    ContentView()
        .environmentObject(InputRuntime())
}
