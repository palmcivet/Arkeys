import AppKit
import SwiftUI
import InputRuntime
import Targeting

/// Full-width AppKit table of locally stored keymap libraries.
struct KeymapAppTable: NSViewRepresentable {
    let targets: [ConfiguredTarget]
    let selectedBundleID: String?
    let isEnabled: Bool
    let onSelect: (String) -> Void

    static let rowHeight = KeymapTableMetrics.rowHeight + 1

    func makeCoordinator() -> KeymapAppTableCoordinator {
        KeymapAppTableCoordinator(onSelect: onSelect)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let tableView = KeymapTableChrome.makeTableView(rowHeight: Self.rowHeight)
        tableView.addTableColumn(KeymapTableChrome.makeFixedColumn(
            id: KeymapAppTableCoordinator.checkColumnID,
            width: KeymapTableMetrics.checkColumnWidth
        ))
        tableView.addTableColumn(KeymapTableChrome.makeFixedColumn(
            id: KeymapAppTableCoordinator.iconColumnID,
            width: KeymapTableMetrics.iconColumnWidth
        ))
        tableView.addTableColumn(KeymapTableChrome.makeFlexibleColumn(id: KeymapAppTableCoordinator.nameColumnID))
        tableView.delegate = context.coordinator
        tableView.dataSource = context.coordinator
        tableView.setAccessibilityLabel(String(localized: "keymap.apps.header"))

        context.coordinator.attach(tableView)
        return KeymapTableChrome.makeScrollView(tableView: tableView)
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.onSelect = onSelect
        context.coordinator.apply(
            targets: targets,
            selectedBundleID: selectedBundleID,
            isEnabled: isEnabled
        )
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: KeymapAppTableCoordinator) {
        coordinator.detach()
    }
}

/// File-level `NSObject` so AppKit delegate callbacks are not MainActor-isolated.
/// Nested types inside a SwiftUI `View` inherit `@MainActor` and can trap when
/// NSTableView calls into an isolated coordinator through Objective-C.
final class KeymapAppTableCoordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    var targets: [ConfiguredTarget] = []
    var selectedBundleID: String?
    var onSelect: (String) -> Void
    weak var tableView: NSTableView?

    private let selectionState = KeymapTableSelectionState()
    private var sizedIconCache: [String: NSImage] = [:]

    init(onSelect: @escaping (String) -> Void) {
        self.onSelect = onSelect
    }

    static let checkColumnID = NSUserInterfaceItemIdentifier("appCheck")
    static let iconColumnID = NSUserInterfaceItemIdentifier("appIcon")
    static let nameColumnID = NSUserInterfaceItemIdentifier("appName")
    static let countLabelTag = 21

    func attach(_ tableView: NSTableView) {
        self.tableView = tableView
    }

    func detach() {
        tableView?.delegate = nil
        tableView?.dataSource = nil
        tableView = nil
    }

    func apply(targets: [ConfiguredTarget], selectedBundleID: String?, isEnabled: Bool) {
        let rowsChanged = !Self.sameRows(self.targets, targets)
        let selectionChanged = self.selectedBundleID != selectedBundleID
        self.targets = targets
        self.selectedBundleID = selectedBundleID
        guard let tableView else { return }
        tableView.isEnabled = isEnabled
        if rowsChanged || tableView.numberOfRows != targets.count {
            selectionState.apply {
                tableView.reloadData()
            }
        } else if selectionChanged {
            refreshCheckmarks()
        }
        retryMissingIcons()
        syncSelection()
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        targets.count
    }

    func tableView(
        _ tableView: NSTableView,
        viewFor tableColumn: NSTableColumn?,
        row: Int
    ) -> NSView? {
        guard targets.indices.contains(row) else { return nil }
        let target = targets[row]

        switch tableColumn?.identifier {
        case Self.checkColumnID:
            let identifier = NSUserInterfaceItemIdentifier("appCheckCell")
            let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView
                ?? KeymapTableChrome.makeImageCell(identifier: identifier, size: 12)
            cell.imageView?.image = checkImage(for: row)
            cell.setAccessibilityElement(false)
            return cell

        case Self.iconColumnID:
            let identifier = NSUserInterfaceItemIdentifier("appIconCell")
            let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView
                ?? KeymapTableChrome.makeImageCell(identifier: identifier, size: 16)
            cell.imageView?.image = icon(for: target.bundleID)
            cell.setAccessibilityElement(false)
            return cell

        default:
            let identifier = NSUserInterfaceItemIdentifier("appNameCell")
            let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView
                ?? makeNameCell(identifier: identifier)
            cell.textField?.stringValue = target.appName
            cell.textField?.toolTip = target.bundleID
            let count = localized(
                "keymap.apps.count",
                default: "\(target.schemes.count) schemes"
            )
            if let countField = cell.viewWithTag(Self.countLabelTag) as? NSTextField {
                countField.stringValue = count
                countField.setAccessibilityElement(false)
            }
            cell.textField?.setAccessibilityElement(false)
            cell.setAccessibilityElement(true)
            cell.setAccessibilityLabel(localized(
                "keymap.apps.row",
                default: "\(target.appName), \(count)"
            ))
            return cell
        }
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !selectionState.isApplying else { return }
        guard let tableView = notification.object as? NSTableView,
              tableView.window != nil,
              tableView.isEnabled else {
            return
        }
        guard tableView.selectedRow >= 0,
              targets.indices.contains(tableView.selectedRow) else {
            return
        }
        let bundleID = targets[tableView.selectedRow].bundleID
        guard bundleID != selectedBundleID else { return }
        selectedBundleID = bundleID
        refreshCheckmarks()
        let handler = onSelect
        DispatchQueue.main.async {
            handler(bundleID)
        }
    }

    private func syncSelection() {
        guard let tableView else { return }
        let row = selectedBundleID.flatMap { id in targets.firstIndex(where: { $0.bundleID == id }) }
        guard KeymapTableChrome.selectedRow(in: tableView) != row else { return }
        selectionState.sync(tableView: tableView, row: row)
    }

    private func refreshCheckmarks() {
        guard let tableView else { return }
        KeymapTableChrome.refreshCheckmarks(
            in: tableView,
            columnID: Self.checkColumnID,
            rowCount: targets.count,
            imageForRow: checkImage(for:)
        )
    }

    private func retryMissingIcons() {
        guard let tableView else { return }
        let iconColumn = tableView.column(withIdentifier: Self.iconColumnID)
        guard iconColumn >= 0 else { return }
        for row in targets.indices where sizedIconCache[targets[row].bundleID] == nil {
            guard let cell = tableView.view(atColumn: iconColumn, row: row, makeIfNecessary: false) as? NSTableCellView else {
                continue
            }
            cell.imageView?.image = icon(for: targets[row].bundleID)
        }
    }

    private func checkImage(for row: Int) -> NSImage? {
        guard targets.indices.contains(row) else { return nil }
        return KeymapTableChrome.checkImage(isSelected: targets[row].bundleID == selectedBundleID)
    }

    private func icon(for bundleID: String) -> NSImage {
        if let cached = sizedIconCache[bundleID] {
            return cached
        }
        guard let raw = RunningAppCatalog.icon(forBundleID: bundleID)?.copy() as? NSImage else {
            return Self.placeholderIcon
        }
        raw.size = NSSize(width: 16, height: 16)
        sizedIconCache[bundleID] = raw
        return raw
    }

    private static let placeholderIcon: NSImage = {
        let image = NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil) ?? NSImage()
        image.isTemplate = true
        image.size = NSSize(width: 16, height: 16)
        return image
    }()

    private func makeNameCell(identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = identifier

        let textField = KeymapTableChrome.makeNameField()
        textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        cell.textField = textField
        cell.addSubview(textField)

        let countField = NSTextField(string: "")
        countField.tag = Self.countLabelTag
        countField.isBordered = false
        countField.isBezeled = false
        countField.drawsBackground = false
        countField.isEditable = false
        countField.isSelectable = false
        countField.alignment = .right
        countField.lineBreakMode = .byTruncatingTail
        countField.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        countField.textColor = .secondaryLabelColor
        countField.setContentHuggingPriority(.required, for: .horizontal)
        countField.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(countField)

        NSLayoutConstraint.activate([
            textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
            textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            countField.leadingAnchor.constraint(greaterThanOrEqualTo: textField.trailingAnchor, constant: 8),
            countField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
            countField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    private static func sameRows(_ lhs: [ConfiguredTarget], _ rhs: [ConfiguredTarget]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        return zip(lhs, rhs).allSatisfy {
            $0.bundleID == $1.bundleID
                && $0.appName == $1.appName
                && $0.schemes.count == $1.schemes.count
        }
    }
}
