import AppKit
import Combine
import Foundation
import MacFindKit

/// UI 状态 + 输入 debounce + 结果操作(设计文档 §5.3 / §6)。
final class SearchViewModel: ObservableObject {
    @Published var queryText: String = ""
    @Published var results: [ResultItem] = []
    @Published var totalCount = 0
    @Published var elapsedMS: Double = 0
    @Published var isSearching = false
    /// ⚠️ 故意不是 `@Published`:选中态由 NSTableView 自己持有,
    /// 若经 SwiftUI 往返会在每次点选时重渲染 + 可能重选整片选中集(明显卡顿)。
    var selected: Set<ResultItem.ID> = []
    /// 查询语法/目录错误;非 nil 时状态栏展示。
    @Published var parseError: String?
    /// 结果操作(如移到废纸篓)失败时的错误。
    @Published var actionError: String?

    private let backend = SpotlightBackend()
    private var debounceWork: DispatchWorkItem?
    private var searchStart: CFAbsoluteTime = 0
    /// 单调递增的查询代数:丢弃过期查询的回调结果。
    private var generation: UInt64 = 0

    init() {
        backend.onResults = { [weak self] token, items in
            guard let self, token == self.generation else { return }   // 过期结果直接丢
            self.results = items
            self.totalCount = self.backend.totalCount
            self.isSearching = false
            self.elapsedMS = (CFAbsoluteTimeGetCurrent() - self.searchStart) * 1000
            if !self.selected.isEmpty, !items.contains(where: { self.selected.contains($0.id) }) {
                self.selected = items.first.map { [$0.id] } ?? []
            }
        }
    }

    /// 输入变化:debounce ~100ms 后查询。
    func updateQuery(_ text: String) {
        queryText = text
        debounceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.run() }
        debounceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.10, execute: work)
    }

    private func run() {
        generation &+= 1   // 使任何在途查询的旧回调失效

        let q: SearchQuery
        do {
            q = try SearchQuery.parse(queryText)
        } catch {
            fail(with: (error as? LocalizedError)?.errorDescription ?? "查询语法错误")
            return
        }
        if let scopeError = q.scopeValidationError() {
            fail(with: scopeError)
            return
        }

        parseError = nil
        actionError = nil
        if q.isEmpty {
            generation &+= 1
            backend.stop()
            results = []
            totalCount = 0
            elapsedMS = 0
            isSearching = false
            return
        }
        isSearching = true
        searchStart = CFAbsoluteTimeGetCurrent()
        backend.search(q, token: generation)
    }

    private func fail(with message: String) {
        parseError = message
        backend.stop()
        results = []
        totalCount = 0
        elapsedMS = 0
        isSearching = false
    }

    // MARK: - 结果操作(§7)

    var selectedItem: ResultItem? {
        if let first = selected.first, let item = results.first(where: { $0.id == first }) { return item }
        return results.first
    }

    /// 搜索框回车:未选中时选中第一条(安全);已选中时才打开。
    /// 避免「敲完字按回车 → 误开第一条文件(可能是脚本)」。
    func handleSubmit() {
        if selected.isEmpty {
            selected = results.first.map { [$0.id] } ?? []
        } else {
            openSelected()
        }
    }

    func open(_ item: ResultItem) {
        NSWorkspace.shared.open(item.url)
    }

    func reveal(_ item: ResultItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    func copyPath(_ item: ResultItem) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(item.path, forType: .string)
    }

    /// 移到废纸篓(可恢复),成功后立即从当前结果里移除。
    func trash(_ item: ResultItem) {
        do {
            try FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
            actionError = nil
            results.removeAll { $0.id == item.id }
            totalCount = max(0, totalCount - 1)
            selected.remove(item.id)
        } catch {
            actionError = "移到废纸篓失败:\(error.localizedDescription)"
        }
    }

    func openSelected() {
        guard let item = selectedItem else { return }
        open(item)
    }

    func revealSelected() {
        guard let item = selectedItem else { return }
        reveal(item)
    }

    func copySelectedPath() {
        guard let item = selectedItem else { return }
        copyPath(item)
    }
}
