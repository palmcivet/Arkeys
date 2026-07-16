import SwiftUI
import UniformTypeIdentifiers
import KeymapCore
import KeymapPlayCover
import InputRuntime
import EditorKit

struct KeymapSettingsView: View {
    @EnvironmentObject private var runtime: InputRuntime
    @StateObject private var editor = KeymapEditorController()
    @State private var importError: String?
    @State private var statusMessage: String?
    @State private var isImporting = false
    @State private var isExporting = false
    @State private var exportDocument: KeymapExportDocument?

    private let registry = KeymapSchemeRegistry(parserTypes: [PlayCoverKeymapParser.self])

    var body: some View {
        Form {
            Section {
                if runtime.targetBundleID == nil {
                    Text("keymap.needTarget")
                        .foregroundStyle(.secondary)
                } else if runtime.schemes.isEmpty {
                    Text("keymap.empty")
                        .foregroundStyle(.secondary)
                } else {
                    Picker("keymap.current", selection: Binding(
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

                    Text(schemeSummaryText)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                HStack {
                    Button("keymap.new") { createNewScheme() }
                        .disabled(runtime.targetBundleID == nil || editor.isActive)
                    Button("keymap.edit") { beginEdit() }
                        .disabled(runtime.activeSchemeID == nil || editor.isActive)
                    Button("keymap.import") { isImporting = true }
                        .disabled(runtime.targetBundleID == nil || editor.isActive)
                    Button("keymap.export") { prepareExport() }
                        .disabled(runtime.activeSchemeID == nil || editor.isActive)
                    Button("keymap.delete", role: .destructive) { deleteActiveScheme() }
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
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.propertyList, .data],
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }
        .fileExporter(
            isPresented: $isExporting,
            document: exportDocument,
            contentType: .propertyList,
            defaultFilename: exportDefaultName
        ) { result in
            if case .failure(let error) = result {
                importError = error.localizedDescription
            }
        }
        .onAppear {
            wireEditorCallbacks()
        }
    }

    private var schemeSummaryText: String {
        let count = runtime.keymap.runnableButtons.count
        let source = localizedSourceName(runtime.keymap.source)
        return String(localized: "keymap.summary \(count) \(source)")
    }

    private var exportDefaultName: String {
        let name = runtime.schemes.first(where: { $0.id == runtime.activeSchemeID })?.name
            ?? String(localized: "keymap.untitled")
        return name
    }

    private func localizedSourceName(_ source: KeymapSourceMeta) -> String {
        switch source {
        case .playCover:
            return String(localized: "keymap.source.playCover")
        case .arkeys:
            return String(localized: "keymap.source.arkeys")
        case .muMu, .ldPlayer, .unknown:
            return String(localized: "keymap.source.unknown")
        }
    }

    private func wireEditorCallbacks() {
        editor.onFinished = { map in
            runtime.keymap = map
            runtime.saveKeymap()
            runtime.isEditing = false
            runtime.onEditorKeyDown = nil
            statusMessage = String(localized: "keymap.saved")
        }
        editor.onCancelled = {
            runtime.isEditing = false
            runtime.onEditorKeyDown = nil
        }
    }

    private func createNewScheme() {
        let name = nextUntitledSchemeName()
        guard runtime.createNewKeymap(name: name) else {
            statusMessage = String(localized: "keymap.needTarget.action")
            return
        }
        statusMessage = String(localized: "keymap.created \(name)")
        beginEdit()
    }

    private func deleteActiveScheme() {
        let name = runtime.schemes.first(where: { $0.id == runtime.activeSchemeID })?.name
            ?? String(localized: "keymap.untitled")
        runtime.deleteActiveScheme()
        statusMessage = String(localized: "keymap.deleted \(name)")
    }

    private func beginEdit() {
        guard let bundleID = runtime.targetBundleID, runtime.activeSchemeID != nil else { return }
        wireEditorCallbacks()
        runtime.isEditing = true
        runtime.onEditorKeyDown = { [weak editor] code, name in
            editor?.handleKeyDown(keyCode: code, name: name)
        }
        editor.start(targetBundleID: bundleID, keymap: runtime.keymap)
    }

    private func prepareExport() {
        importError = nil
        do {
            let data = try registry.exportKeymap(runtime.keymap, scheme: .playCover)
            exportDocument = KeymapExportDocument(data: data)
            isExporting = true
        } catch {
            importError = error.localizedDescription
        }
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
            statusMessage = String(localized: "keymap.imported \(suggested)")
        } catch {
            importError = error.localizedDescription
        }
    }

    private func nextUntitledSchemeName() -> String {
        let base = String(localized: "keymap.untitled")
        let existing = Set(runtime.schemes.map(\.name))
        guard existing.contains(base) else { return base }
        var index = 2
        while existing.contains("\(base) \(index)") {
            index += 1
        }
        return "\(base) \(index)"
    }
}

struct KeymapExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.propertyList] }
    static var writableContentTypes: [UTType] { [.propertyList] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
