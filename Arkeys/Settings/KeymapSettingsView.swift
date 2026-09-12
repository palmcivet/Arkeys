import SwiftUI
import UniformTypeIdentifiers
import KeymapCore
import KeymapPlayCover
import InputRuntime
import Targeting

struct KeymapSettingsView: View {
    @EnvironmentObject private var runtime: InputRuntime
    var session: EditorSession
    @StateObject private var highlight = TargetHighlightController(copy: .app)
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
        .sheet(isPresented: $isPickingApp) {
            appPicker(titleKey: "picker.title", confirmKey: "picker.bindSelected") { app in
                runtime.bind(bundleID: app.bundleIdentifier, appName: app.name)
                isPickingApp = false
            }
        }
        .sheet(isPresented: $isCopyingToApp) {
            appPicker(titleKey: "keymap.schemes.copyTo.title", confirmKey: "keymap.schemes.copyTo.confirm") { app in
                copyActiveScheme(to: app)
                isCopyingToApp = false
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
                Button("common.delete", role: .destructive) {
                    confirmPendingDelete()
                }
            }
            Button("common.cancel", role: .cancel) {
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

    private var hasSelectedApp: Bool {
        runtime.targetBundleID != nil
    }

    private var schemesSection: some View {
        Section {
            schemeStatusRow

            KeymapSchemeTable(
                schemes: runtime.schemes,
                selectedID: runtime.activeSchemeID,
                isEnabled: hasSelectedApp && !runtime.isEditing,
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
                    .help("keymap.schemes.new")
                    .accessibilityLabel("keymap.schemes.new")
                    .disabled(!hasSelectedApp || runtime.isEditing)

                    Button {
                        requestDeleteActiveScheme()
                    } label: {
                        Image(systemName: "minus")
                    }
                    .help("common.delete")
                    .accessibilityLabel("common.delete")
                    .disabled(!hasSelectedApp || runtime.activeSchemeID == nil || runtime.isEditing)
                }
                .buttonStyle(.borderless)
                .controlSize(.small)

                Spacer(minLength: 8)
                    .layoutPriority(1)

                Button("keymap.schemes.import") {
                    isImporting = true
                }
                .disabled(!hasSelectedApp || runtime.isEditing)
                .fixedSize()
            }
        } header: {
            Text("keymap.schemes.header")
        } footer: {
            SettingsFooter("keymap.schemes.footer")
        }
    }

    @ViewBuilder
    private var schemeStatusRow: some View {
        if !hasSelectedApp {
            Text("keymap.schemes.needTargetApp")
                .foregroundStyle(.secondary)
                .settingsMultilineLeading()
        } else if runtime.schemes.isEmpty {
            Text("keymap.schemes.empty")
                .foregroundStyle(.secondary)
                .settingsMultilineLeading()
        } else {
            HStack(spacing: 8) {
                if runtime.keymap.unresolvedButtonCount > 0 {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .accessibilityHidden(true)
                }
                Text(schemeSummaryText)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Button("keymap.schemes.edit") {
                    beginEdit()
                }
                .disabled(runtime.isEditing)
                .fixedSize()

                Menu {
                    Button("keymap.schemes.rename") { renameRequest += 1 }
                        .disabled(runtime.activeSchemeID == nil)
                    Button("keymap.schemes.export") { prepareExport() }
                        .disabled(runtime.activeSchemeID == nil)
                    Button("keymap.schemes.copyTo") { isCopyingToApp = true }
                        .disabled(runtime.activeSchemeID == nil)
                } label: {
                    Text("keymap.schemes.more")
                }
                .menuStyle(.button)
                .disabled(runtime.isEditing)
                .fixedSize()
            }
        }
    }

    private var schemeSummaryText: String {
        let count = runtime.keymap.runnableButtons.count
        let unresolved = runtime.keymap.unresolvedButtonCount
        if unresolved > 0 {
            return localized(
                "keymap.schemes.summary.unbound",
                default: "\(count) keys · \(unresolved) unbound (?)"
            )
        }
        return localized(
            "keymap.schemes.summary",
            default: "\(count) keys"
        )
    }

    private var exportDefaultName: String {
        let name = runtime.schemes.first(where: { $0.id == runtime.activeSchemeID })?.name
            ?? String(localized: "keymap.schemes.untitled")
        return name
    }

    private var alertTitle: String {
        switch presentedAlert {
        case .delete(.app(let app)):
            localized(
                "keymap.apps.delete.title",
                default: "Delete All Schemes for “\(app.appName)”?"
            )
        case .delete(.scheme(let scheme)):
            localized(
                "keymap.schemes.delete.title",
                default: "Delete Scheme “\(scheme.name)”?"
            )
        case .error(let message):
            message
        case nil:
            ""
        }
    }

    private func alertMessage(for alert: PresentedAlert) -> String? {
        switch alert {
        case .delete(.app(let app)):
            localized(
                "keymap.apps.delete.message",
                default: "This will delete \(app.schemes.count) saved schemes. You can’t undo this action."
            )
        case .delete(.scheme):
            String(localized: "keymap.schemes.delete.message")
        case .error:
            nil
        }
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
            presentedAlert = .error(String(localized: "keymap.schemes.copyTo.failed"))
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
        let base = String(localized: "keymap.schemes.untitled")
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
