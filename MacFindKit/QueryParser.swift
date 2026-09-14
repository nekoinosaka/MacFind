import Foundation

/// 查询语法错误。
public enum QueryParseError: Error, Equatable, LocalizedError {
    case invalidSize(String)
    case invalidDate(String)
    case unterminatedQuote

    public var errorDescription: String? {
        switch self {
        case .invalidSize(let s):   return "无效的大小:\(s)(示例:size:>10M)"
        case .invalidDate(let s):   return "无效的日期:\(s)(示例:date:7d / date:today / date:>2024-01-01)"
        case .unterminatedQuote:    return "引号未闭合"
        }
    }
}

/// `kind:` 过滤器取值。
public enum KindFilter: String, Equatable {
    case file, dir, symlink
}

/// `size:` 比较。
public struct SizeConstraint: Equatable {
    public enum Op: String, Equatable {
        case gt = ">"
        case ge = ">="
        case lt = "<"
        case le = "<="
    }
    public let op: Op
    public let bytes: Int64
    public init(op: Op, bytes: Int64) {
        self.op = op
        self.bytes = bytes
    }
}

/// 解析后的查询。`predicate()` 产出 `NSMetadataQuery` 用的 `NSPredicate`。
///
/// 语法(§5.1):`literal` / `!literal` / `ext:` / `size:` / `date:` / `kind:` / `in:` / `name:`
public struct SearchQuery: Equatable {
    public var literals: [String] = []
    public var excludedLiterals: [String] = []
    public var extensions: [String] = []
    public var excludedExtensions: [String] = []
    public var sizes: [SizeConstraint] = []
    public var modifiedAfter: Date?
    public var kinds: Set<KindFilter> = []
    public var scope: String?

    public init() {}

    public var isEmpty: Bool {
        literals.isEmpty && excludedLiterals.isEmpty
            && extensions.isEmpty && excludedExtensions.isEmpty
            && sizes.isEmpty && modifiedAfter == nil && kinds.isEmpty
    }

    /// `in:` 指向的目录是否存在且为目录;有问题时返回可直接展示的错误文案。
    public func scopeValidationError(fileManager: FileManager = .default) -> String? {
        guard let scope else { return nil }
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: scope, isDirectory: &isDir), isDir.boolValue else {
            return "目录不存在或不是目录:\(scope)"
        }
        return nil
    }

    // MARK: - Parsing

    public static func parse(_ input: String, now: Date = Date()) throws -> SearchQuery {
        var q = SearchQuery()
        for raw in try tokenize(input) {
            var token = raw
            var negated = false
            if token.hasPrefix("!") { negated = true; token.removeFirst() }
            else if token.hasPrefix("-") { negated = true; token.removeFirst() }
            if token.isEmpty { continue }

            guard let colon = token.firstIndex(of: ":") else {
                if negated { q.excludedLiterals.append(token) } else { q.literals.append(token) }
                continue
            }
            let key = token[token.startIndex..<colon].lowercased()
            let value = String(token[token.index(after: colon)...])

            switch key {
            case "ext":
                let exts = value.split(separator: ",").map { $0.lowercased() }.filter { !$0.isEmpty }
                if negated { q.excludedExtensions.append(contentsOf: exts) }
                else { q.extensions.append(contentsOf: exts) }

            case "size":
                let c = try parseSize(value)
                q.sizes.append(c)

            case "date":
                q.modifiedAfter = try parseDate(value, now: now)

            case "kind":
                for k in value.split(separator: ",") {
                    if let kf = KindFilter(rawValue: k.lowercased()) { q.kinds.insert(kf) }
                }

            case "in":
                q.scope = (value as NSString).expandingTildeInPath

            case "name":
                if negated { q.excludedLiterals.append(value) } else { q.literals.append(value) }

            default:
                // 未知 key 当作普通文本(含冒号)
                if negated { q.excludedLiterals.append(token) } else { q.literals.append(token) }
            }
        }
        return q
    }

    static func tokenize(_ input: String) throws -> [String] {
        var tokens: [String] = []
        var current = ""
        var inQuotes = false
        var started = false
        for ch in input {
            if ch == "\"" { inQuotes.toggle(); started = true; continue }
            if ch == " " || ch == "\t" {
                if inQuotes { current.append(ch) }
                else if started { tokens.append(current); current = ""; started = false }
                continue
            }
            current.append(ch)
            started = true
        }
        if inQuotes { throw QueryParseError.unterminatedQuote }
        if started { tokens.append(current) }
        return tokens
    }

    static func parseSize(_ s: String) throws -> SizeConstraint {
        var op = SizeConstraint.Op.ge
        var rest = s
        for prefix in [">=", "<=", ">", "<"] where rest.hasPrefix(prefix) {
            op = SizeConstraint.Op(rawValue: prefix) ?? .ge
            rest.removeFirst(prefix.count)
            break
        }
        var multiplier: Int64 = 1
        if let last = rest.last {
            switch Character(last.uppercased()) {
            case "K": multiplier = 1024; rest.removeLast()
            case "M": multiplier = 1024 * 1024; rest.removeLast()
            case "G": multiplier = 1024 * 1024 * 1024; rest.removeLast()
            default: break
            }
        }
        guard let n = Int64(rest), n >= 0 else { throw QueryParseError.invalidSize(s) }
        let (bytes, overflow) = n.multipliedReportingOverflow(by: multiplier)
        guard !overflow else { throw QueryParseError.invalidSize(s) }   // ⚠️ 防 Int64 溢出崩溃
        return SizeConstraint(op: op, bytes: bytes)
    }

    static func parseDate(_ s: String, now: Date) throws -> Date {
        let lower = s.lowercased()
        if lower == "today" { return Calendar.current.startOfDay(for: now) }
        if lower.hasSuffix("d"), let n = Int(lower.dropLast()) {
            return Calendar.current.date(byAdding: .day, value: -n, to: now) ?? now
        }
        var rest = s
        if rest.hasPrefix(">=") { rest.removeFirst(2) }
        else if rest.hasPrefix(">") { rest.removeFirst(1) }
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.timeZone = .current
        df.locale = Locale(identifier: "en_US_POSIX")
        if let d = df.date(from: rest) { return d }
        throw QueryParseError.invalidDate(s)
    }

    // MARK: - Predicate

    /// 构建 Spotlight 谓词;查询为空时返回 `nil`(匹配全部)。
    public func predicate() -> NSPredicate? {
        var preds: [NSPredicate] = []

        for lit in literals where !lit.isEmpty {
            preds.append(NSPredicate(format: "kMDItemFSName LIKE[c] %@", Self.likePattern(lit)))
        }
        for lit in excludedLiterals where !lit.isEmpty {
            preds.append(NSPredicate(format: "NOT (kMDItemFSName LIKE[c] %@)", Self.likePattern(lit)))
        }
        if !extensions.isEmpty {
            let subs = extensions.map {
                NSPredicate(format: "kMDItemFSName LIKE[c] %@", "*." + Self.escapeLike($0))
            }
            preds.append(Self.orCompound(subs))
        }
        if !excludedExtensions.isEmpty {
            let subs = excludedExtensions.map {
                NSPredicate(format: "kMDItemFSName LIKE[c] %@", "*." + Self.escapeLike($0))
            }
            preds.append(NSCompoundPredicate(notPredicateWithSubpredicate: Self.orCompound(subs)))
        }
        for s in sizes {
            preds.append(NSPredicate(format: "kMDItemFSSize \(s.op.rawValue) %lld", s.bytes))
        }
        if let after = modifiedAfter {
            preds.append(NSPredicate(format: "kMDItemContentModificationDate >= %@", after as NSDate))
        }
        if !kinds.isEmpty {
            let subs = kinds.map { kind -> NSPredicate in
                switch kind {
                case .dir:     return NSPredicate(format: "kMDItemContentType == %@", "public.folder")
                case .symlink: return NSPredicate(format: "kMDItemContentType == %@", "public.symlink")
                case .file:    return NSPredicate(format: "kMDItemContentType != %@", "public.folder")
                }
            }
            preds.append(Self.orCompound(subs))
        }

        if preds.isEmpty { return nil }
        if preds.count == 1 { return preds[0] }   // ⚠️ NSMetadataQuery 拒绝单子谓词的 compound
        return NSCompoundPredicate(andPredicateWithSubpredicates: preds)
    }

    /// `NSMetadataQuery` 不接受只有一个子谓词的 `NSCompoundPredicate`。
    static func orCompound(_ subs: [NSPredicate]) -> NSPredicate {
        if subs.count == 1 { return subs[0] }
        return NSCompoundPredicate(orPredicateWithSubpredicates: subs)
    }

    static func escapeLike(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
    }
    static func likePattern(_ s: String) -> String {
        "*" + escapeLike(s) + "*"
    }
}
