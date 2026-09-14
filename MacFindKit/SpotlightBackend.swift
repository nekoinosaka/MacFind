import Foundation

/// 进程内 `NSMetadataQuery` 封装(设计文档 §3)。查询系统 Spotlight 索引,不重建索引。
///
/// ⚠️ `NSMetadataQuery` 只接受 **metadata 查询谓词**;`NSPredicate(value: true)` 会在
/// `setPredicate:` 抛异常。空查询一律用合法的全匹配谓词(`kMDItemFSName LIKE "*"`)。
public final class SpotlightBackend {
    private let query = NSMetadataQuery()
    private var observers: [NSObjectProtocol] = []

    /// 最多回传的结果条数。
    public let maxResults: Int
    public private(set) var totalCount = 0
    public var onResults: (([ResultItem]) -> Void)?

    /// 合法的「匹配全部」谓词。
    public static func matchAllPredicate() -> NSPredicate {
        NSPredicate(format: "kMDItemFSName LIKE[c] %@", "*")
    }

    public init(maxResults: Int = 500) {
        self.maxResults = maxResults
        query.searchScopes = [NSMetadataQueryLocalComputerScope]
        query.sortDescriptors = [NSSortDescriptor(key: NSMetadataItemFSContentChangeDateKey, ascending: false)]
        query.notificationBatchingInterval = 0.1

        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: .NSMetadataQueryDidFinishGathering,
                                       object: query, queue: .main) { [weak self] _ in
            self?.handleUpdate()
        })
        observers.append(nc.addObserver(forName: .NSMetadataQueryDidUpdate,
                                       object: query, queue: .main) { [weak self] _ in
            self?.handleUpdate()
        })
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    public func search(_ q: SearchQuery) {
        query.stop()
        query.predicate = q.predicate() ?? Self.matchAllPredicate()
        if let scope = q.scope {
            query.searchScopes = [URL(fileURLWithPath: scope)]
        } else {
            query.searchScopes = [NSMetadataQueryLocalComputerScope]
        }
        query.start()
    }

    public func stop() { query.stop() }

    private func handleUpdate() {
        query.disableUpdates()
        defer { query.enableUpdates() }

        totalCount = query.resultCount
        var items: [ResultItem] = []
        let n = min(query.resultCount, maxResults)
        items.reserveCapacity(n)
        for i in 0..<n {
            guard let md = query.result(at: i) as? NSMetadataItem,
                  let item = Self.makeItem(from: md) else { continue }
            items.append(item)
        }
        onResults?(items)
    }

    private static func makeItem(from md: NSMetadataItem) -> ResultItem? {
        guard let path = md.value(forAttribute: NSMetadataItemPathKey) as? String else { return nil }
        let url = URL(fileURLWithPath: path)

        var size = (md.value(forAttribute: NSMetadataItemFSSizeKey) as? NSNumber)?.int64Value ?? 0
        var modified = (md.value(forAttribute: NSMetadataItemContentModificationDateKey) as? Date) ?? .distantPast
        var isDirectory = false
        var isSymlink = false

        if let rv = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey]) {
            isDirectory = rv.isDirectory ?? false
            isSymlink = rv.isSymbolicLink ?? false
            if let s = rv.fileSize { size = Int64(s) }
            if let d = rv.contentModificationDate { modified = d }
        }

        let name = (md.value(forAttribute: NSMetadataItemFSNameKey) as? String) ?? url.lastPathComponent
        return ResultItem(path: path, name: name, size: size,
                          modified: modified, isDirectory: isDirectory, isSymlink: isSymlink)
    }
}
