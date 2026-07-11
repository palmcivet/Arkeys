import SwiftUI
import UniformTypeIdentifiers
import KeymapCore
import KeymapPlayCover
import Injection
import InputRuntime
import EditorKit

struct ContentView: View {
    @EnvironmentObject var runtime: InputRuntime
    @StateObject private var editor = KeymapEditorController()
    @State private var importError: String?
    @State private var isImporting = false

    private let registry = KeymapSchemeRegistry(parserTypes: [PlayCoverKeymapParser.self])

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Striker Settings")
                    .font(.title2)

                Group {
                    Toggle("Enabled", isOn: $runtime.isEnabled)

                    HStack {
                        Text("Target")
                        Text(runtime.targetAppName)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer()
                        Button("Bind Frontmost") {
                            runtime.bindFrontmostApp()
                        }
                    }

                    Text(runtime.targetBundleID ?? "(no bundle id)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)

                    Text("Keymap")
                        .font(.headline)
                    Text(runtime.keymapSummary)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)

                    HStack {
                        Button("Edit Keymap") { beginEdit() }
                            .disabled(runtime.targetBundleID == nil || editor.isActive)
                        Button("Import PlayCover…") { isImporting = true }
                        Button("Clear") { runtime.clearKeymap() }
                            .disabled(runtime.targetBundleID == nil)
                    }

                    if let importError {
                        Text(importError)
                            .font(.caption)
                            .foregroundStyle(.red)
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

                Text("Grant Accessibility in System Settings. Import a PlayCover .plist/.playmap or edit overlay bindings on the target window.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .frame(minWidth: 440, minHeight: 520)
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.propertyList, .data],
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
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
        }
        editor.onCancelled = {
            runtime.isEditing = false
            runtime.onEditorKeyDown = nil
        }
    }

    private func beginEdit() {
        guard let bundleID = runtime.targetBundleID else { return }
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
            runtime.applyImportedKeymap(map)
        } catch {
            importError = error.localizedDescription
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(InputRuntime())
}
