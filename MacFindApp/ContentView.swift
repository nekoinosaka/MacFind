import AppKit
import MacFindKit
import SwiftUI

/// 主面板:搜索框 + 结果表 + 状态行(§6.1)。
struct ContentView: View {
    @StateObject private var vm = SearchViewModel()
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()
            resultsTable
            Divider()
            statusBar
        }
        .frame(minWidth: 760, minHeight: 440)
        .onAppear { searchFocused = true }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("搜索文件名 · 支持 ext: size: date: kind: in: 与 ! 取反",
                      text: Binding(get: { vm.queryText }, set: { vm.updateQuery($0) }))
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .focused($searchFocused)
                .onSubmit { vm.handleSubmit() }
            if vm.isSearching {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var resultsTable: some View {
        Table(vm.results, selection: $vm.selected) {
            TableColumn("名称") { item in
                HStack(spacing: 6) {
                    Image(systemName: iconName(for: item))
                        .foregroundStyle(item.isDirectory ? Color.accentColor : .secondary)
                    Text(item.name).lineLimit(1)
                }
            }
            .width(min: 200, ideal: 320)

            TableColumn("大小") { item in
                Text(Self.sizeString(item))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .width(min: 60, ideal: 90, max: 120)

            TableColumn("修改时间") { item in
                Text(Self.dateString(item.modified))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .width(min: 130, ideal: 150, max: 190)

            TableColumn("路径") { item in
                Text(displayPath(item.path))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .width(min: 240, ideal: 380)
        }
        .contextMenu(forSelectionType: ResultItem.ID.self) { ids in
            if let item = item(for: ids) {
                Button("打开") { NSWorkspace.shared.open(item.url) }
                Button("在 Finder 中显示") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
                Divider()
                Button("复制路径") { copy(item.path) }
            }
        } primaryAction: { ids in
            if let item = item(for: ids) { NSWorkspace.shared.open(item.url) }
        }
    }

    private var statusBar: some View {
        HStack {
            if let error = vm.parseError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            } else if vm.results.isEmpty {
                Text(vm.isSearching ? "搜索中…" : "无匹配")
            } else {
                Text("\(vm.totalCount) 条匹配" + (vm.totalCount > vm.results.count ? " · 显示前 \(vm.results.count)" : ""))
            }
            Spacer()
            Text(String(format: "%.0f ms", vm.elapsedMS))
        }
        .font(.caption)
        .foregroundStyle(vm.parseError == nil ? Color.secondary : Color.orange)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - helpers

    private func item(for ids: Set<ResultItem.ID>) -> ResultItem? {
        guard let id = ids.first else { return vm.selectedItem }
        return vm.results.first { $0.id == id }
    }

    private func iconName(for item: ResultItem) -> String {
        if item.isDirectory { return "folder" }
        if item.isSymlink { return "link" }
        return "doc"
    }

    private func displayPath(_ path: String) -> String {
        (path as NSString).abbreviatingWithTildeInPath
    }

    private func copy(_ s: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(s, forType: .string)
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
        if item.isDirectory { return "—" }
        return byteFormatter.string(fromByteCount: item.size)
    }

    static func dateString(_ d: Date) -> String {
        if d == .distantPast { return "—" }
        return dateFormatter.string(from: d)
    }
}
