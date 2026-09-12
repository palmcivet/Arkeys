import AppKit

final class KeymapTableSelectionState {
    private(set) var isApplying = false

    func apply(_ action: () -> Void) {
        isApplying = true
        defer { isApplying = false }
        action()
    }

    func sync(tableView: NSTableView, row: Int?) {
        guard KeymapTableChrome.selectedRow(in: tableView) != row else { return }
        apply {
            if let row {
                tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            } else {
                tableView.deselectAll(nil)
            }
        }
    }
}

enum KeymapTableMetrics {
    static let rowHeight: CGFloat = 20
    static let intercellSpacingHeight: CGFloat = 1
    /// `NSScrollView` `.bezelBorder` inset on each edge.
    static let bezelInset: CGFloat = 2
    static let checkColumnWidth: CGFloat = 22
    static let iconColumnWidth: CGFloat = 22

    /// Clip-view height for `visibleRows` fully on screen, with no scroller.
    /// `NSTableView` steps each row by `rowHeight + intercellSpacing.height`.
    static func height(visibleRows: Int, rowHeight: CGFloat = KeymapTableMetrics.rowHeight) -> CGFloat {
        CGFloat(visibleRows) * (rowHeight + intercellSpacingHeight) + bezelInset * 2
    }
}

enum KeymapTableChrome {
    static func makeTableView(rowHeight: CGFloat = KeymapTableMetrics.rowHeight) -> NSTableView {
        let tableView = NSTableView()
        tableView.headerView = nil
        tableView.style = .fullWidth
        tableView.selectionHighlightStyle = .regular
        tableView.rowSizeStyle = .custom
        tableView.rowHeight = rowHeight
        tableView.usesAutomaticRowHeights = false
        tableView.intercellSpacing = NSSize(width: 3, height: KeymapTableMetrics.intercellSpacingHeight)
        tableView.allowsEmptySelection = false
        tableView.allowsMultipleSelection = false
        tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.backgroundColor = .controlBackgroundColor
        return tableView
    }

    static func makeScrollView(tableView: NSTableView) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets()
        scrollView.borderType = .bezelBorder
        scrollView.drawsBackground = true
        return scrollView
    }

    static func makeFixedColumn(id: NSUserInterfaceItemIdentifier, width: CGFloat) -> NSTableColumn {
        let column = NSTableColumn(identifier: id)
        column.width = width
        column.minWidth = width
        column.maxWidth = width
        column.resizingMask = []
        return column
    }

    static func makeFlexibleColumn(id: NSUserInterfaceItemIdentifier) -> NSTableColumn {
        let column = NSTableColumn(identifier: id)
        column.resizingMask = .autoresizingMask
        return column
    }

    static func makeImageCell(identifier: NSUserInterfaceItemIdentifier, size: CGFloat) -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = identifier

        let imageView = NSImageView()
        imageView.imageScaling = .scaleProportionallyDown
        imageView.setAccessibilityElement(false)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        cell.imageView = imageView
        cell.addSubview(imageView)

        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: cell.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: size),
            imageView.heightAnchor.constraint(equalToConstant: size),
        ])
        return cell
    }

    static func makeNameField() -> NSTextField {
        let textField = NSTextField(string: "")
        textField.isBordered = false
        textField.isBezeled = false
        textField.drawsBackground = false
        textField.isEditable = false
        textField.isSelectable = false
        textField.lineBreakMode = .byTruncatingTail
        textField.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        textField.translatesAutoresizingMaskIntoConstraints = false
        return textField
    }

    static func checkImage(isSelected: Bool) -> NSImage? {
        guard isSelected else { return nil }
        let image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)
        image?.isTemplate = true
        return image
    }

    static func selectedRow(in tableView: NSTableView) -> Int? {
        tableView.selectedRow >= 0 ? tableView.selectedRow : nil
    }

    static func refreshCheckmarks(
        in tableView: NSTableView,
        columnID: NSUserInterfaceItemIdentifier,
        rowCount: Int,
        imageForRow: (Int) -> NSImage?
    ) {
        let checkColumn = tableView.column(withIdentifier: columnID)
        guard checkColumn >= 0 else { return }
        for row in 0..<rowCount {
            guard let cell = tableView.view(atColumn: checkColumn, row: row, makeIfNecessary: false) as? NSTableCellView else {
                continue
            }
            cell.imageView?.image = imageForRow(row)
        }
    }
}
