import Foundation

/// 一条搜索结果。
public struct ResultItem: Identifiable, Hashable {
    public let path: String
    public let name: String
    public let size: Int64
    public let modified: Date
    public let isDirectory: Bool
    public let isSymlink: Bool

    public init(path: String, name: String, size: Int64,
                modified: Date, isDirectory: Bool, isSymlink: Bool) {
        self.path = path
        self.name = name
        self.size = size
        self.modified = modified
        self.isDirectory = isDirectory
        self.isSymlink = isSymlink
    }

    public var id: String { path }
    public var url: URL { URL(fileURLWithPath: path) }
}
