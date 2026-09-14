import AppKit
import Combine
import Foundation
import MacFindKit

/// UI 状态 + 输入 debounce + 结果操作(设计文档 §5.3 / §6)。
///
/// 注意:选中态**不在这里**。它由 `NSTableView` 自己持有,通过 `ResultsTableHandle`
/// 按需读取;若把它搬进 `@Published` 走 SwiftUI 往返,点选会触发重渲染并和表格抢选中态。
final class SearchViewModel: ObservableObject {
    @Published var queryText: String = ""
    @Published var results: [ResultItem] = []
    @Published var totalCount = 0
    @Published var elapsedMS: Double = 0
    @Published var isSearching = false
    /// 查询语法/目录错误;非 nil 时状态栏展示。
    @Published var parseError: String?
    /// 结果操作(如移到废纸篓)失败时的错误。
    @Published var actionError: String?

    /// 由 `ContentView` 在出现时注入,用于与表格选中态交互。
    var table: ResultsTableHandle?

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
        }
    }

    /// 当前选中的结果(直接问表格)。
    var currentItem: ResultItem? { table?.currentItem?() }

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

    // MARK: - 结果操作(设计文档 §7)

    /// 搜索框回车:已选中则打开,否则选中第一条(避免误开)。
    func handleSubmit() {
        if let item = currentItem {
            open(item)
        } else {
            table?.selectFirstRow?()
        }
    }

    func open(_ item: ResultItem) {
        // 异步打开:`-[NSWorkspace openURL:]` 会同步阻塞主线程(实测 ~290ms 的 LaunchServices 调用)
        NSWorkspace.shared.open(item.url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            if let error { NSLog("MacFind open failed: %@", error.localizedDescription) }
        }
    }

    func reveal(_ item: ResultItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    func copyPath(_ item: ResultItem) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(item.path, forType: .string)
    }

    /// 移到废纸篓(可恢复),成功后从当前结果里移除。文件操作用后台队列,避免卡主线程。
    func trash(_ item: ResultItem) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
                DispatchQueue.main.async {
                    self.actionError = nil
                    self.results.removeAll { $0.id == item.id }
                    self.totalCount = max(0, self.totalCount - 1)
                }
            } catch {
                DispatchQueue.main.async {
                    self.actionError = "移到废纸篓失败:\(error.localizedDescription)"
                }
            }
        }
    }
}
