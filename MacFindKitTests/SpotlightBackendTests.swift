import XCTest

@testable import MacFindKit

/// 端到端验证:谓词能被 `NSMetadataQuery` 接受,且能返回真实结果。
/// 依赖本机 Spotlight 索引(设计文档 §10 已是前提)。
final class SpotlightBackendTests: XCTestCase {

    private func runSearch(_ text: String, timeout: TimeInterval = 15) throws -> (items: [ResultItem], total: Int) {
        let query = try SearchQuery.parse(text)
        XCTAssertNotNil(query.predicate(), "非空查询应有谓词")

        let backend = SpotlightBackend(maxResults: 50)
        let exp = expectation(description: "spotlight: \(text)")
        var items: [ResultItem] = []
        var total = 0
        backend.onResults = { _, result in
            items = result
            total = backend.totalCount
            exp.fulfill()
        }
        backend.search(query, token: 1)
        wait(for: [exp], timeout: timeout)
        return (items, total)
    }

    /// 空查询谓词必须合法(回归:曾用 NSPredicate(value:true) 导致 setPredicate 抛异常)。
    func testMatchAllPredicateIsValid() {
        let backend = SpotlightBackend(maxResults: 1)
        let exp = expectation(description: "matchAll")
        backend.onResults = { _, _ in exp.fulfill() }
        backend.search(SearchQuery())   // 空查询 → 走 matchAll
        wait(for: [exp], timeout: 15)
    }

    /// 回调必须原样回传发起查询时的 token(供调用方丢弃过期结果)。
    func testTokenIsEchoed() {
        let backend = SpotlightBackend(maxResults: 1)
        let exp = expectation(description: "token")
        var seen: UInt64?
        var fulfilled = false
        backend.onResults = { token, _ in
            seen = token
            if !fulfilled { fulfilled = true; exp.fulfill() }
        }
        backend.search(SearchQuery(), token: 42)
        wait(for: [exp], timeout: 15)
        XCTAssertEqual(seen, 42)
    }

    /// 无效 scope 不应崩溃,且应回退到全局(不抛异常、能拿到结果)。
    func testInvalidScopeDoesNotCrash() {
        let backend = SpotlightBackend(maxResults: 1)
        let exp = expectation(description: "bad scope")
        backend.onResults = { _, _ in exp.fulfill() }
        guard let q = try? SearchQuery.parse("in:/definitely/not/here") else {
            return XCTFail("parse failed")
        }
        backend.search(q, token: 1)   // 应回退为全局 scope
        wait(for: [exp], timeout: 15)
    }

    /// 在 /Applications 里搜 Xcode(必然被 Spotlight 索引)。
    func testSearchApplicationsForXcode() throws {
        let result = try runSearch("in:/Applications Xcode")
        XCTAssertGreaterThan(result.total, 0, "应至少命中 Xcode 相关条目")
        XCTAssertTrue(result.items.contains { $0.path.lowercased().contains("xcode") },
                      "结果应包含 Xcode 路径,实际: \(result.items.map(\.path).prefix(5))")
    }

    /// ext: 过滤应只返回对应扩展名。
    func testExtensionFilter() throws {
        let result = try runSearch("in:/Applications ext:app")
        XCTAssertGreaterThan(result.total, 0)
        for item in result.items {
            XCTAssertTrue(item.name.lowercased().hasSuffix(".app"), "非 .app: \(item.name)")
        }
    }
}
