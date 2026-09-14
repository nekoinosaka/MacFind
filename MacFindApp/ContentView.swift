import AppKit
import MacFindKit
import SwiftUI

/// 主面板:搜索框 + 结果表 + 状态行(设计文档 §6.1)。
struct ContentView: View {
    @StateObject private var vm = SearchViewModel()
    @State private var tableHandle = ResultsTableHandle()
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
        .onAppear {
            vm.table = tableHandle
            searchFocused = true
        }
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
        ResultsTableView(items: vm.results,
                         handle: tableHandle,
                         onOpen: { vm.open($0) },
                         onTrash: { vm.trash($0) })
    }

    private var statusBar: some View {
        HStack {
            if let error = vm.parseError ?? vm.actionError {
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
        .foregroundStyle((vm.parseError ?? vm.actionError) == nil ? Color.secondary : Color.orange)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}
