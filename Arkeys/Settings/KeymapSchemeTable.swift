import AppKit
import Carbon.HIToolbox
import SwiftUI
import KeymapCore

/// Full-width AppKit table: compact rows, rectangular selection, inline rename.
struct KeymapSchemeTable: NSViewRepresentable {
    let schemes: [KeymapSchemeMeta]
    let selectedID: UUID?
    let isEnabled: Bool
    let renameRequest: Int
    let onSelect: (UUID) -> Void
    let onRename: (UUID, String) -> Void

    func makeCoordinator() -> KeymapSchemeTableCoordinator {
        KeymapSchemeTableCoordinator(onSelect: onSelect, onRename: onRename)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let tableView = KeymapSchemeTableView()
        KeymapTableChrome.configure(tableView)
        tableView.onRenameSelection = { [weak coordinator = context.coordinator] in
            coordinator?.beginRenameOfSelection()
        }
        tableView.addTableColumn(KeymapTableChrome.makeFixedColumn(
            id: KeymapSchemeTableCoordinator.checkColumnID,
            width: KeymapTableMetrics.checkColumnWidth
        ))
        tableView.addTableColumn(KeymapTableChrome.makeFlexibleColumn(id: KeymapSchemeTableCoordinator.nameColumnID))
        tableView.delegate = context.coordinator
        tableView.dataSource = context.coordinator
        tableView.target = context.coordinator
        tableView.doubleAction = #selector(KeymapSchemeTableCoordinator.doubleClicked(_:))
        tableView.setAccessibilityLabel(String(localized: "keymap.schemes.header"))

        context.coordinator.attach(tableView)
        return KeymapTableChrome.makeScrollView(tableView: tableView)
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onSelect = onSelect
        coordinator.onRename = onRename
        coordinator.apply(
            schemes: schemes,
            selectedID: selectedID,
            isEnabled: isEnabled
        )
        if renameRequest != coordinator.handledRenameRequest {
            coordinator.handledRenameRequest = renameRequest
            DispatchQueue.main.async {
                coordinator.beginRenameOfSelection()
            }
        }
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: KeymapSchemeTableCoordinator) {
        coordinator.detach()
    }
}

/// File-level `NSObject` so AppKit delegate callbacks are not MainActor-isolated.
final class KeymapSchemeTableCoordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    var schemes: [KeymapSchemeMeta] = []
    var selectedID: UUID?
    var onSelect: (UUID) -> Void
    var onRename: (UUID, String) -> Void
    var handledRenameRequest = 0
    weak var tableView: NSTableView?

    private let selectionState = KeymapTableSelectionState()
    private var editingSchemeID: UUID?
    private var nameBeforeEdit = ""

    init(onSelect: @escaping (UUID) -> Void, onRename: @escaping (UUID, String) -> Void) {
        self.onSelect = onSelect
        self.onRename = onRename
    }

    static let checkColumnID = NSUserInterfaceItemIdentifier("check")
    static let nameColumnID = NSUserInterfaceItemIdentifier("scheme")

    func attach(_ tableView: NSTableView) {
        self.tableView = tableView
    }

    func detach() {
        tableView?.delegate = nil
        tableView?.dataSource = nil
        tableView?.target = nil
        tableView = nil
    }

    func apply(schemes: [KeymapSchemeMeta], selectedID: UUID?, isEnabled: Bool) {
        let schemesChanged = !Self.sameRows(self.schemes, schemes)
        let selectionChanged = self.selectedID != selectedID
        self.schemes = schemes
        self.selectedID = selectedID
        guard let tableView, editingSchemeID == nil else { return }
        tableView.isEnabled = isEnabled
        if schemesChanged || tableView.numberOfRows != schemes.count {
            selectionState.apply {
                tableView.reloadData()
            }
        } else if selectionChanged {
            refreshCheckmarks()
        }
        syncSelection()
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        schemes.count
    }

    func tableView(
        _ tableView: NSTableView,
        viewFor tableColumn: NSTableColumn?,
        row: Int
    ) -> NSView? {
        if tableColumn?.identifier == Self.checkColumnID {
            let identifier = NSUserInterfaceItemIdentifier("checkCell")
            let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView
                ?? KeymapTableChrome.makeImageCell(identifier: identifier, size: 12)
            cell.imageView?.image = checkImage(for: row)
            cell.setAccessibilityElement(false)
            return cell
        }

        guard schemes.indices.contains(row) else { return nil }
        let identifier = NSUserInterfaceItemIdentifier("schemeCell")
        let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView
            ?? makeNameCell(identifier: identifier)
        cell.textField?.stringValue = schemes[row].name
        let isEditing = editingSchemeID == schemes[row].id
        cell.textField?.setAccessibilityElement(isEditing)
        cell.setAccessibilityElement(!isEditing)
        cell.setAccessibilityLabel(schemes[row].name)
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !selectionState.isApplying, editingSchemeID == nil else { return }
        guard let tableView = notification.object as? NSTableView,
              tableView.window != nil,
              tableView.isEnabled else {
            return
        }
        guard tableView.selectedRow >= 0,
              schemes.indices.contains(tableView.selectedRow) else {
            return
        }
        let id = schemes[tableView.selectedRow].id
        guard id != selectedID else { return }
        selectedID = id
        refreshCheckmarks()
        let handler = onSelect
        DispatchQueue.main.async {
            handler(id)
        }
    }

    @objc func doubleClicked(_ sender: Any?) {
        guard let tableView, tableView.clickedRow >= 0, tableView.isEnabled else { return }
        guard tableView.clickedColumn != 0 else { return }
        beginRename(row: tableView.clickedRow)
    }

    func beginRenameOfSelection() {
        guard let tableView, tableView.isEnabled else { return }
        let row = selectedID.flatMap { id in schemes.firstIndex(where: { $0.id == id }) }
            ?? (tableView.selectedRow >= 0 ? tableView.selectedRow : nil)
        guard let row else { return }
        beginRename(row: row)
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let textField = obj.object as? NSTextField else { return }
        finishEditing(textField, commit: true)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)),
           let textField = control as? NSTextField {
            finishEditing(textField, commit: false)
            tableView?.window?.makeFirstResponder(tableView)
            return true
        }
        // Return commits and restores table focus. `finishEditing` is idempotent
        // if resigning first responder also posts `controlTextDidEndEditing`.
        if commandSelector == #selector(NSResponder.insertNewline(_:)),
           let textField = control as? NSTextField {
            finishEditing(textField, commit: true)
            tableView?.window?.makeFirstResponder(tableView)
            return true
        }
        return false
    }

    private func beginRename(row: Int) {
        guard let tableView, schemes.indices.contains(row) else { return }
        let nameColumn = tableView.column(withIdentifier: Self.nameColumnID)
        guard nameColumn >= 0,
              let cell = tableView.view(atColumn: nameColumn, row: row, makeIfNecessary: true) as? NSTableCellView,
              let textField = cell.textField else {
            return
        }
        editingSchemeID = schemes[row].id
        nameBeforeEdit = schemes[row].name
        textField.isEditable = true
        textField.isSelectable = true
        textField.setAccessibilityElement(true)
        cell.setAccessibilityElement(false)
        tableView.window?.makeFirstResponder(textField)
        textField.currentEditor()?.selectAll(nil)
    }

    private func finishEditing(_ textField: NSTextField, commit: Bool) {
        guard let id = editingSchemeID else { return }
        editingSchemeID = nil
        textField.isEditable = false
        textField.isSelectable = false
        textField.setAccessibilityElement(false)
        textField.superview?.setAccessibilityElement(true)

        let name = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if commit, !name.isEmpty, name != nameBeforeEdit {
            textField.stringValue = name
            let handler = onRename
            DispatchQueue.main.async {
                handler(id, name)
            }
        } else {
            textField.stringValue = nameBeforeEdit
        }
    }

    private func syncSelection() {
        guard let tableView else { return }
        let row = selectedID.flatMap { id in schemes.firstIndex(where: { $0.id == id }) }
        selectionState.sync(tableView: tableView, row: row)
    }

    private func refreshCheckmarks() {
        guard let tableView else { return }
        KeymapTableChrome.refreshCheckmarks(
            in: tableView,
            columnID: Self.checkColumnID,
            rowCount: schemes.count,
            imageForRow: checkImage(for:)
        )
    }

    private func checkImage(for row: Int) -> NSImage? {
        guard schemes.indices.contains(row) else { return nil }
        return KeymapTableChrome.checkImage(isSelected: schemes[row].id == selectedID)
    }

    private func makeNameCell(identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = identifier

        let textField = KeymapTableChrome.makeNameField()
        textField.delegate = self
        textField.focusRingType = .none
        cell.textField = textField
        cell.addSubview(textField)

        NSLayoutConstraint.activate([
            textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
            textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
            textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    private static func sameRows(_ lhs: [KeymapSchemeMeta], _ rhs: [KeymapSchemeMeta]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        return zip(lhs, rhs).allSatisfy { $0.id == $1.id && $0.name == $1.name }
    }
}

private final class KeymapSchemeTableView: NSTableView {
    var onRenameSelection: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        // Return/Enter and F2 match Finder: rename the selected scheme.
        let isRenameKey =
            event.keyCode == UInt16(kVK_Return)
            || event.keyCode == UInt16(kVK_ANSI_KeypadEnter)
            || event.keyCode == UInt16(kVK_F2)
        if isRenameKey, isEnabled, selectedRow >= 0, onRenameSelection != nil {
            onRenameSelection?()
            return
        }
        super.keyDown(with: event)
    }
}
