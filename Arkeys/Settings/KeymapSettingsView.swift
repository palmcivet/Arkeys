import SwiftUI
import UniformTypeIdentifiers
import KeymapCore
import KeymapPlayCover
import InputRuntime

struct KeymapSettingsView: View {
    @EnvironmentObject private var runtime: InputRuntime
    var session: EditorSession
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
                    .disabled(runtime.isEditing)

                    Text(schemeSummaryText)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Toggle("keymap.showOverlay", isOn: $runtime.showKeymapOverlay)
            } footer: {
                SettingsFooter("keymap.showOverlay.footer")
            }

            Section {
                Picker("keymap.buttonShape", selection: $runtime.keymapButtonShape) {
                    Text("keymap.buttonShape.circle").tag(KeymapButtonShape.circle)
                    Text("keymap.buttonShape.rectangle").tag(KeymapButtonShape.rectangle)
                }
                .pickerStyle(.segmented)
            }

            Section {
                HStack {
                    Button("keymap.new") { createNewScheme() }
                        .disabled(runtime.targetBundleID == nil || runtime.isEditing)
                    Button("keymap.edit") { beginEdit() }
                        .disabled(runtime.activeSchemeID == nil || runtime.isEditing)
                    Button("keymap.import") { isImporting = true }
                        .disabled(runtime.targetBundleID == nil || runtime.isEditing)
                    Button("keymap.export") { prepareExport() }
                        .disabled(runtime.activeSchemeID == nil || runtime.isEditing)
                    Button("keymap.delete", role: .destructive) { deleteActiveScheme() }
                        .disabled(runtime.activeSchemeID == nil || runtime.isEditing)
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
            session.onSaved = {
                statusMessage = String(localized: "keymap.saved")
            }
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
        session.start()
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
