import SwiftUI
import UniformTypeIdentifiers
import KeymapCore
import KeymapPlayCover
import InputRuntime
import Targeting

struct KeymapSettingsView: View {
    @EnvironmentObject private var runtime: InputRuntime
    var session: EditorSession
    @StateObject private var highlight = TargetHighlightController()
    @State private var isImporting = false
    @State private var isExporting = false
    @State private var exportDocument: KeymapExportDocument?
    @State private var isPickingApp = false
    @State private var isCopyingToApp = false
    @State private var renameRequest = 0
    @State private var presentedAlert: PresentedAlert?

    private let registry = KeymapSchemeRegistry(parserTypes: [PlayCoverKeymapParser.self])
    private static let appVisibleRows = 4
    private static let schemeVisibleRows = 3

    var body: some View {
        Form {
            appsSection
            schemesSection

            // Per-scheme Auto Clicker settings belong here when implemented.
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
                presentedAlert = .error(error.localizedDescription)
            }
        }
        .sheet(isPresented: $isPickingApp, onDismiss: hideHighlight) {
            appPicker(titleKey: "picker.title", confirmKey: "picker.bind") { app in
                runtime.bind(bundleID: app.bundleIdentifier, appName: app.name)
                isPickingApp = false
                highlight.hide()
            }
        }
        .sheet(isPresented: $isCopyingToApp, onDismiss: hideHighlight) {
            appPicker(titleKey: "keymap.copyTo.title", confirmKey: "keymap.copyTo.confirm") { app in
                copyActiveScheme(to: app)
                isCopyingToApp = false
                highlight.hide()
            }
        }
        .alert(
            alertTitle,
            isPresented: Binding(
                get: { presentedAlert != nil },
                set: { if !$0 { presentedAlert = nil } }
            ),
            presenting: presentedAlert
        ) { alert in
            if case .delete = alert {
                Button("keymap.delete", role: .destructive) {
                    confirmPendingDelete()
                }
            }
            Button("picker.cancel", role: .cancel) {
                presentedAlert = nil
            }
        } message: { alert in
            if let message = alertMessage(for: alert) {
                Text(message)
            }
        }
    }

    /// Stored libraries plus the current target when it has no schemes yet.
    private var displayedTargets: [ConfiguredTarget] {
        var list = runtime.configuredTargets
        if let id = runtime.targetBundleID, !list.contains(where: { $0.bundleID == id }) {
            list.append(ConfiguredTarget(
                bundleID: id,
                appName: runtime.targetAppName ?? id,
                schemes: runtime.schemes,
                activeSchemeID: runtime.activeSchemeID
            ))
            list.sort { $0.appName.localizedCaseInsensitiveCompare($1.appName) == .orderedAscending }
        }
        return list
    }

    private var selectedTarget: ConfiguredTarget? {
        displayedTargets.first { $0.bundleID == runtime.targetBundleID }
    }

    private var appsSection: some View {
        Section {
            KeymapAppTable(
                targets: displayedTargets,
                selectedBundleID: runtime.targetBundleID,
                isEnabled: !runtime.isEditing,
                onSelect: { bundleID in
                    guard let target = displayedTargets.first(where: { $0.bundleID == bundleID }) else {
                        return
                    }
                    runtime.bind(bundleID: target.bundleID, appName: target.appName)
                }
            )
            .frame(height: KeymapTableMetrics.height(
                visibleRows: Self.appVisibleRows,
                rowHeight: KeymapAppTable.rowHeight
            ))

            HStack(spacing: 8) {
                Button {
                    isPickingApp = true
                } label: {
                    Image(systemName: "plus")
                }
                .help("keymap.apps.add")
                .accessibilityLabel("keymap.apps.add")
                .disabled(runtime.isEditing)

                Button {
                    requestDeleteSelectedApp()
                } label: {
                    Image(systemName: "minus")
                }
                .help("keymap.apps.remove")
                .accessibilityLabel("keymap.apps.remove")
                .disabled(runtime.targetBundleID == nil || runtime.isEditing)
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
        } header: {
            Text("keymap.apps.header")
        } footer: {
            SettingsFooter("keymap.apps.footer")
        }
    }

    private var schemesSection: some View {
        Section {
            if runtime.targetBundleID == nil {
                Text("keymap.needTarget")
                    .foregroundStyle(.secondary)
                    .settingsMultilineLeading()
            } else {
                if runtime.schemes.isEmpty {
                    Text("keymap.empty")
                        .foregroundStyle(.secondary)
                        .settingsMultilineLeading()
                } else {
                    HStack(spacing: 8) {
                        Text(schemeSummaryText)
                            .foregroundStyle(runtime.keymap.unresolvedButtonCount > 0 ? Color.orange : .secondary)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Button("keymap.edit") {
                            beginEdit()
                        }
                        .disabled(runtime.isEditing)
                        .fixedSize()

                        Menu {
                            Button("keymap.rename") { renameRequest += 1 }
                                .disabled(runtime.activeSchemeID == nil)
                            Button("keymap.export") { prepareExport() }
                                .disabled(runtime.activeSchemeID == nil)
                            Button("keymap.copyTo") { isCopyingToApp = true }
                                .disabled(runtime.activeSchemeID == nil)
                        } label: {
                            Text("keymap.more")
                        }
                        .menuStyle(.button)
                        .disabled(runtime.isEditing)
                        .fixedSize()
                    }
                }

                KeymapSchemeTable(
                    schemes: runtime.schemes,
                    selectedID: runtime.activeSchemeID,
                    isEnabled: !runtime.isEditing,
                    renameRequest: renameRequest,
                    onSelect: { runtime.selectScheme(id: $0) },
                    onRename: runtime.renameScheme
                )
                .frame(height: KeymapTableMetrics.height(visibleRows: Self.schemeVisibleRows))

                HStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Button {
                            createNewScheme()
                        } label: {
                            Image(systemName: "plus")
                        }
                        .help("keymap.new")
                        .accessibilityLabel("keymap.new")
                        .disabled(runtime.isEditing)

                        Button {
                            requestDeleteActiveScheme()
                        } label: {
                            Image(systemName: "minus")
                        }
                        .help("keymap.delete")
                        .accessibilityLabel("keymap.delete")
                        .disabled(runtime.activeSchemeID == nil || runtime.isEditing)
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)

                    Spacer(minLength: 8)
                        .layoutPriority(1)

                    Button("keymap.import") {
                        isImporting = true
                    }
                    .disabled(runtime.isEditing)
                    .fixedSize()
                }
            }
        } header: {
            Text("keymap.schemes.header")
        } footer: {
            SettingsFooter("keymap.selection.footer")
        }
    }

    private var schemeSummaryText: String {
        let count = runtime.keymap.runnableButtons.count
        let unresolved = runtime.keymap.unresolvedButtonCount
        if unresolved > 0 {
            return String(localized: "keymap.summary.invalid \(count) \(unresolved)")
        }
        return String(localized: "keymap.summary \(count)")
    }

    private var exportDefaultName: String {
        let name = runtime.schemes.first(where: { $0.id == runtime.activeSchemeID })?.name
            ?? String(localized: "keymap.untitled")
        return name
    }

    private var alertTitle: String {
        switch presentedAlert {
        case .delete(.app(let app)):
            String(localized: "keymap.apps.delete.title \(app.appName)")
        case .delete(.scheme(let scheme)):
            String(localized: "keymap.schemes.delete.title \(scheme.name)")
        case .error(let message):
            message
        case nil:
            ""
        }
    }

    private func alertMessage(for alert: PresentedAlert) -> String? {
        switch alert {
        case .delete(.app(let app)):
            String(localized: "keymap.apps.delete.message \(app.schemes.count)")
        case .delete(.scheme):
            String(localized: "keymap.schemes.delete.message")
        case .error:
            nil
        }
    }

    private func hideHighlight() {
        highlight.hide()
    }

    private func appPicker(
        titleKey: LocalizedStringKey,
        confirmKey: LocalizedStringKey,
        onSelect: @escaping (SelectableApp) -> Void
    ) -> AppPickerSheet {
        AppPickerSheet(
            titleKey: titleKey,
            confirmKey: confirmKey,
            apps: runtime.selectableApps(),
            currentBundleID: runtime.targetBundleID,
            highlight: highlight,
            onSelect: onSelect
        )
    }

    private func createNewScheme() {
        let name = nextUntitledSchemeName()
        guard runtime.createNewKeymap(name: name) else { return }
        renameRequest += 1
    }

    private func requestDeleteActiveScheme() {
        guard let scheme = runtime.schemes.first(where: { $0.id == runtime.activeSchemeID }) else {
            return
        }
        presentedAlert = .delete(.scheme(scheme))
    }

    private func requestDeleteSelectedApp() {
        guard let target = selectedTarget else { return }
        if target.schemes.isEmpty {
            runtime.deleteTarget(bundleID: target.bundleID)
        } else {
            presentedAlert = .delete(.app(target))
        }
    }

    private func confirmPendingDelete() {
        guard case .delete(let pending) = presentedAlert else { return }
        switch pending {
        case .app(let app):
            runtime.deleteTarget(bundleID: app.bundleID)
        case .scheme:
            runtime.deleteActiveScheme()
        }
        presentedAlert = nil
    }

    private func copyActiveScheme(to app: SelectableApp) {
        guard runtime.copyActiveScheme(toBundleID: app.bundleIdentifier, appName: app.name) else {
            presentedAlert = .error(String(localized: "keymap.copyTo.failed"))
            return
        }
    }

    private func beginEdit() {
        session.start()
    }

    private func prepareExport() {
        do {
            let data = try registry.exportKeymap(runtime.keymap, scheme: .playCover)
            exportDocument = KeymapExportDocument(data: data)
            isExporting = true
        } catch {
            presentedAlert = .error(error.localizedDescription)
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            guard let url = urls.first else { return }
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            let map = try registry.importKeymap(data: data, filename: url.lastPathComponent)
            let suggested = url.deletingPathExtension().lastPathComponent
            runtime.applyImportedKeymap(map, suggestedName: suggested)
        } catch {
            presentedAlert = .error(error.localizedDescription)
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

private enum PendingDelete {
    case app(ConfiguredTarget)
    case scheme(KeymapSchemeMeta)
}

private enum PresentedAlert {
    case delete(PendingDelete)
    case error(String)
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
