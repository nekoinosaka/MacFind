import AppKit
import MacFindKit
import QuickLookUI
import SwiftUI

/// 结果列表:AppKit `NSTableView`(设计文档 §3/§17)。
///
/// 用 AppKit 而非 SwiftUI `Table`,是为了支持**行拖拽导出文件**
/// (`pasteboardWriterForRow` 提供 file URL),以及双击打开、右键菜单、Return 打开。
struct ResultsTableView: NSViewRepresentable {
    var items: [ResultItem]
    @Binding var selection: Set<ResultItem.ID>
    var onOpen: (ResultItem) -> Void
    var onTrash: (ResultItem) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let tableView = KeyTableView()
        tableView.dataSource = context.coordinator
        tableView.delegate = context.coordinator
        tableView.allowsMultipleSelection = true
        tableView.allowsEmptySelection = true
        tableView.rowHeight = 22
        tableView.style = .inset
        tableView.target = context.coordinator
        tableView.doubleAction = #selector(Coordinator.doubleClicked(_:))
        tableView.menu = context.coordinator.makeContextMenu()
        // 允许把结果拖到 Finder / 其他 App;`.delete` 是「拖到废纸篓」所必需的
        tableView.setDraggingSourceOperationMask([.copy, .delete], forLocal: false)
        tableView.onSpace = { [weak coordinator = context.coordinator] in coordinator?.togglePreview() }
        context.coordinator.tableView = tableView

        Self.addColumn(to: tableView, id: .name, title: "名称", width: 320, min: 180, max: 900)
        Self.addColumn(to: tableView, id: .size, title: "大小", width: 90, min: 60, max: 120)
        Self.addColumn(to: tableView, id: .date, title: "修改时间", width: 150, min: 120, max: 200)
        Self.addColumn(to: tableView, id: .path, title: "路径", width: 380, min: 200, max: 1200)
        tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        tableView.headerView = NSTableHeaderView()

        let scroll = NSScrollView()
        scroll.documentView = tableView
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        return scroll
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let tableView = scrollView.documentView as? NSTableView else { return }

        let ids = items.map(\.id)
        if ids != context.coordinator.lastIDs {
            context.coordinator.lastIDs = ids
            tableView.reloadData()
        }
        context.coordinator.reconcileSelection(in: tableView)
    }

    private static func addColumn(to tableView: NSTableView, id: NSUserInterfaceItemIdentifier,
                                  title: String, width: CGFloat, min: CGFloat, max: CGFloat) {
        let column = NSTableColumn(identifier: id)
        column.title = title
        column.width = width
        column.minWidth = min
        column.maxWidth = max
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate,
                             QLPreviewPanelDataSource, QLPreviewPanelDelegate {
        var parent: ResultsTableView
        weak var tableView: NSTableView?
        var lastIDs: [String] = []
        private var isSyncingSelection = false

        init(_ parent: ResultsTableView) { self.parent = parent }

        var items: [ResultItem] { parent.items }

        // MARK: DataSource

        func numberOfRows(in tableView: NSTableView) -> Int { items.count }

        /// 拖拽导出:提供文件 URL(多选拖拽时 AppKit 会逐行调用)。
        func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
            guard row >= 0, row < items.count else { return nil }
            let pb = NSPasteboardItem()
            pb.setString(items[row].url.absoluteString, forType: .fileURL)
            pb.setString(items[row].path, forType: .string)
            return pb
        }

        // MARK: Delegate

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard row >= 0, row < items.count, let columnID = tableColumn?.identifier else { return nil }
            let item = items[row]

            switch columnID {
            case .name:
                let cell = cellView(tableView, identifier: .nameCell, withImage: true)
                cell.imageView?.image = Self.icon(for: item)
                cell.textField?.stringValue = item.name
                cell.textField?.font = .systemFont(ofSize: 13)
                return cell

            case .size:
                let cell = cellView(tableView, identifier: .textCell, withImage: false)
                cell.textField?.stringValue = Self.sizeString(item)
                cell.textField?.alignment = .right
                cell.textField?.textColor = .secondaryLabelColor
                return cell

            case .date:
                let cell = cellView(tableView, identifier: .textCell, withImage: false)
                cell.textField?.stringValue = Self.dateString(item.modified)
                cell.textField?.textColor = .secondaryLabelColor
                return cell

            case .path:
                let cell = cellView(tableView, identifier: .textCell, withImage: false)
                cell.textField?.stringValue = (item.path as NSString).abbreviatingWithTildeInPath
                cell.textField?.textColor = .secondaryLabelColor
                return cell

            default:
                return nil
            }
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !isSyncingSelection, let tableView = notification.object as? NSTableView else { return }
            parent.selection = selectedIDs(in: tableView)
        }

        /// 外部(绑定的)选中态 → 表格
        func reconcileSelection(in tableView: NSTableView) {
            let desired = parent.selection
            let current = selectedIDs(in: tableView)
            guard desired != current else { return }

            var indexes = IndexSet()
            for (i, item) in items.enumerated() where desired.contains(item.id) { indexes.insert(i) }
            isSyncingSelection = true
            tableView.selectRowIndexes(indexes, byExtendingSelection: false)
            isSyncingSelection = false
        }

        private func selectedIDs(in tableView: NSTableView) -> Set<ResultItem.ID> {
            Set(tableView.selectedRowIndexes.compactMap { $0 < items.count ? items[$0].id : nil })
        }

        // MARK: Actions

        @objc func doubleClicked(_ sender: Any?) {
            openSelectedRow()
        }

        @objc func menuOpen(_ sender: Any?) { openSelectedRow() }

        @objc func menuReveal(_ sender: Any?) {
            guard let item = menuTargetItem() else { return }
            NSWorkspace.shared.activateFileViewerSelecting([item.url])
        }

        @objc func menuCopyPath(_ sender: Any?) {
            guard let item = menuTargetItem() else { return }
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(item.path, forType: .string)
        }

        @objc func menuTrash(_ sender: Any?) {
            guard let item = menuTargetItem() else { return }
            parent.onTrash(item)
        }

        private func openSelectedRow() {
            guard let item = menuTargetItem() else { return }
            parent.onOpen(item)
        }

        /// 右键/双击作用的目标:优先点击的那一行(`clickedRow`),其次选中行,最后第一行。
        private func menuTargetItem() -> ResultItem? {
            if let tableView {
                let clicked = tableView.clickedRow
                if clicked >= 0, clicked < items.count { return items[clicked] }
                if let sel = tableView.selectedRowIndexes.first, sel < items.count { return items[sel] }
            }
            return items.first
        }

        // MARK: QuickLook(Space)

        func togglePreview() {
            guard let panel = QLPreviewPanel.shared() else { return }
            if panel.isVisible {
                panel.orderOut(nil)
                return
            }
            guard !items.isEmpty else { return }
            if let tableView, let row = tableView.selectedRowIndexes.first, row < items.count {
                panel.currentPreviewItemIndex = row
            } else {
                panel.currentPreviewItemIndex = 0
            }
            panel.dataSource = self
            panel.delegate = self
            panel.reloadData()
            panel.makeKeyAndOrderFront(nil)
        }

        func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { items.count }

        func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
            guard index >= 0, index < items.count else { return nil }
            return items[index].url as NSURL
        }

        /// Space 再按一次关闭(与系统 QuickLook 一致)。
        func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
            if event.type == .keyDown, event.keyCode == 49 {
                panel.orderOut(nil)
                return true
            }
            return false
        }

        func makeContextMenu() -> NSMenu {
            let menu = NSMenu()
            menu.addItem(withTitle: "打开", action: #selector(menuOpen(_:)), keyEquivalent: "").target = self
            menu.addItem(withTitle: "在 Finder 中显示", action: #selector(menuReveal(_:)), keyEquivalent: "").target = self
            menu.addItem(withTitle: "复制路径", action: #selector(menuCopyPath(_:)), keyEquivalent: "").target = self
            menu.addItem(.separator())
            let trash = menu.addItem(withTitle: "移到废纸篓", action: #selector(menuTrash(_:)), keyEquivalent: "")
            trash.target = self
            trash.image = NSImage(systemSymbolName: "trash", accessibilityDescription: nil)
            return menu
        }

        // MARK: Formatting

        private func cellView(_ tableView: NSTableView, identifier: NSUserInterfaceItemIdentifier,
                              withImage: Bool) -> NSTableCellView {
            if let reused = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView {
                return reused
            }
            let cell = NSTableCellView()
            cell.identifier = identifier

            let textField = NSTextField(labelWithString: "")
            textField.lineBreakMode = .byTruncatingMiddle
            textField.translatesAutoresizingMaskIntoConstraints = false
            textField.font = .systemFont(ofSize: 13)
            cell.addSubview(textField)
            cell.textField = textField

            if withImage {
                let imageView = NSImageView()
                imageView.translatesAutoresizingMaskIntoConstraints = false
                cell.addSubview(imageView)
                cell.imageView = imageView
                NSLayoutConstraint.activate([
                    imageView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                    imageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                    imageView.widthAnchor.constraint(equalToConstant: 16),
                    imageView.heightAnchor.constraint(equalToConstant: 16),
                    textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 6),
                    textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                    textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                ])
            } else {
                NSLayoutConstraint.activate([
                    textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                    textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                    textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                ])
            }
            return cell
        }

        private static func icon(for item: ResultItem) -> NSImage? {
            let name = item.isDirectory ? "folder" : (item.isSymlink ? "link" : "doc")
            let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
            image?.isTemplate = true
            return image
        }

        private static let byteFormatter: ByteCountFormatter = {
            let f = ByteCountFormatter()
            f.countStyle = .file
            return f
        }()

        private static let dateFormatter: DateFormatter = {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd HH:mm"
            return f
        }()

        static func sizeString(_ item: ResultItem) -> String {
            item.isDirectory ? "—" : byteFormatter.string(fromByteCount: item.size)
        }

        static func dateString(_ date: Date) -> String {
            date == .distantPast ? "—" : dateFormatter.string(from: date)
        }
    }
}

/// Return 键 = 打开;Space 键 = QuickLook 预览。
final class KeyTableView: NSTableView {
    var onSpace: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 76 {   // Return / Enter
            if let target, let action = doubleAction {
                NSApp.sendAction(action, to: target, from: self)
            }
            return
        }
        if event.keyCode == 49 {                          // Space
            onSpace?()
            return
        }
        super.keyDown(with: event)
    }
}

extension NSUserInterfaceItemIdentifier {
    static let name = NSUserInterfaceItemIdentifier("name")
    static let size = NSUserInterfaceItemIdentifier("size")
    static let date = NSUserInterfaceItemIdentifier("date")
    static let path = NSUserInterfaceItemIdentifier("path")
    static let nameCell = NSUserInterfaceItemIdentifier("nameCell")
    static let textCell = NSUserInterfaceItemIdentifier("textCell")
}
