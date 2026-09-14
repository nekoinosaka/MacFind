import AppKit
import MacFindKit
import QuickLookUI
import SwiftUI

/// SwiftUI/VM 侧按需读取或操作表格选中态,**不让选中态经 SwiftUI 广播**
/// (否则每次点选都会重渲染并与 NSTableView 抢选中态,造成可见卡顿)。
final class ResultsTableHandle {
    var currentItem: (() -> ResultItem?)?
    var selectFirstRow: (() -> Void)?
}

/// 结果列表:AppKit `NSTableView`(设计文档 §3/§17)。
///
/// 功能:行拖拽导出、拖到废纸篓、双击/Return 打开、Space QuickLook、右键菜单、**点表头排序**。
/// 选中态完全由 NSTableView 自己持有,SwiftUI 不参与。
struct ResultsTableView: NSViewRepresentable {
    var items: [ResultItem]
    var handle: ResultsTableHandle?
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
        tableView.setDraggingSourceOperationMask([.copy, .delete], forLocal: false)   // .delete:拖到废纸篓
        tableView.onSpace = { [weak coordinator = context.coordinator] in coordinator?.togglePreview() }

        Self.addColumn(to: tableView, id: .name, title: "名称", width: 320, min: 180, max: 900, sortKey: "name")
        Self.addColumn(to: tableView, id: .size, title: "大小", width: 90, min: 60, max: 120, sortKey: "size")
        Self.addColumn(to: tableView, id: .date, title: "修改时间", width: 150, min: 120, max: 200, sortKey: "date")
        Self.addColumn(to: tableView, id: .path, title: "路径", width: 380, min: 200, max: 1200, sortKey: "path")
        tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        tableView.headerView = NSTableHeaderView()
        tableView.sortDescriptors = context.coordinator.sortDescriptors   // 显示排序指示器

        context.coordinator.tableView = tableView
        handle?.currentItem = { [weak coordinator = context.coordinator] in coordinator?.currentItem() }
        handle?.selectFirstRow = { [weak coordinator = context.coordinator] in coordinator?.selectFirstRow() }

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
        guard ids != context.coordinator.lastIDs else { return }   // 结果集没变就啥都不做
        let keepID = context.coordinator.currentItem()?.id
        context.coordinator.lastIDs = ids
        context.coordinator.reset(to: items)
        tableView.reloadData()
        context.coordinator.restoreSelection(keepID, in: tableView)
    }

    private static func addColumn(to tableView: NSTableView, id: NSUserInterfaceItemIdentifier,
                                  title: String, width: CGFloat, min: CGFloat, max: CGFloat,
                                  sortKey: String) {
        let column = NSTableColumn(identifier: id)
        column.title = title
        column.width = width
        column.minWidth = min
        column.maxWidth = max
        column.resizingMask = .autoresizingMask
        column.sortDescriptorPrototype = NSSortDescriptor(key: sortKey, ascending: sortKey == "date" ? false : true)
        tableView.addTableColumn(column)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate,
                             QLPreviewPanelDataSource, QLPreviewPanelDelegate {
        var parent: ResultsTableView
        weak var tableView: NSTableView?
        var lastIDs: [String] = []

        /// 当前显示顺序(在 `items` 基础上应用排序)。
        private var displayItems: [ResultItem] = []
        var sortDescriptors: [NSSortDescriptor] = [NSSortDescriptor(key: "date", ascending: false)]

        init(_ parent: ResultsTableView) { self.parent = parent }

        // MARK: 数据/排序

        func reset(to newItems: [ResultItem]) {
            displayItems = newItems
            applyCurrentSort()
        }

        private func applyCurrentSort() {
            let key = sortDescriptors.first?.key ?? "date"
            let ascending = sortDescriptors.first?.ascending ?? false
            displayItems.sort { a, b in
                let c = Self.compare(a, b, key: key)
                if c == .orderedSame { return a.path < b.path }   // 稳定:同名按路径
                return ascending ? c == .orderedAscending : c == .orderedDescending
            }
        }

        private static func compare(_ a: ResultItem, _ b: ResultItem, key: String) -> ComparisonResult {
            switch key {
            case "name": return a.name.localizedStandardCompare(b.name)
            case "size": return a.size == b.size ? .orderedSame : (a.size < b.size ? .orderedAscending : .orderedDescending)
            case "path": return a.path.localizedStandardCompare(b.path)
            default:
                if a.modified == b.modified { return .orderedSame }
                return a.modified < b.modified ? .orderedAscending : .orderedDescending
            }
        }

        func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
            sortDescriptors = tableView.sortDescriptors
            applyCurrentSort()
            tableView.reloadData()
        }

        func numberOfRows(in tableView: NSTableView) -> Int { displayItems.count }

        /// 拖拽导出:提供文件 URL(多选拖拽时 AppKit 逐行调用)。
        func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
            guard row >= 0, row < displayItems.count else { return nil }
            let pb = NSPasteboardItem()
            pb.setString(displayItems[row].url.absoluteString, forType: .fileURL)
            pb.setString(displayItems[row].path, forType: .string)
            return pb
        }

        // MARK: 选中态(仅表格持有)

        func currentItem() -> ResultItem? {
            guard let tableView, let row = tableView.selectedRowIndexes.first, row < displayItems.count else { return nil }
            return displayItems[row]
        }

        func selectFirstRow() {
            guard let tableView, !displayItems.isEmpty else { return }
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            tableView.scrollRowToVisible(0)
        }

        func restoreSelection(_ id: ResultItem.ID?, in tableView: NSTableView) {
            if let id, let row = displayItems.firstIndex(where: { $0.id == id }) {
                tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            } else {
                tableView.deselectAll(nil)
            }
        }

        // MARK: Delegate

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard row >= 0, row < displayItems.count, let columnID = tableColumn?.identifier else { return nil }
            let item = displayItems[row]

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

        // MARK: QuickLook(Space)

        func togglePreview() {
            guard let panel = QLPreviewPanel.shared() else { return }
            if panel.isVisible {
                panel.orderOut(nil)
                return
            }
            guard !displayItems.isEmpty else { return }
            if let tableView, let row = tableView.selectedRowIndexes.first, row < displayItems.count {
                panel.currentPreviewItemIndex = row
            } else {
                panel.currentPreviewItemIndex = 0
            }
            panel.dataSource = self
            panel.delegate = self
            panel.reloadData()
            panel.makeKeyAndOrderFront(nil)
        }

        func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { displayItems.count }

        func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
            guard index >= 0, index < displayItems.count else { return nil }
            return displayItems[index].url as NSURL
        }

        /// Space 再按一次关闭(与系统 QuickLook 一致)。
        func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
            if event.type == .keyDown, event.keyCode == 49 {
                panel.orderOut(nil)
                return true
            }
            return false
        }

        // MARK: Actions

        /// ⚠️只有真正双击到「行」才打开;双击表头/空白区(`clickedRow < 0`)不动作。
        @objc func doubleClicked(_ sender: Any?) {
            guard let tableView, tableView.clickedRow >= 0 else { return }
            openTargetItem()
        }

        @objc func menuOpen(_ sender: Any?) { openTargetItem() }

        @objc func menuReveal(_ sender: Any?) {
            guard let item = targetItem() else { return }
            NSWorkspace.shared.activateFileViewerSelecting([item.url])
        }

        @objc func menuCopyPath(_ sender: Any?) {
            guard let item = targetItem() else { return }
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(item.path, forType: .string)
        }

        @objc func menuTrash(_ sender: Any?) {
            guard let item = targetItem() else { return }
            parent.onTrash(item)
        }

        private func openTargetItem() {
            guard let item = targetItem() else { return }
            parent.onOpen(item)
        }

        /// 右键作用的目标:优先点击行,其次选中行。
        private func targetItem() -> ResultItem? {
            if let tableView {
                let clicked = tableView.clickedRow
                if clicked >= 0, clicked < displayItems.count { return displayItems[clicked] }
            }
            return currentItem()
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

        // MARK: Cells

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
