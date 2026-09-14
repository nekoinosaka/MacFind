import XCTest

@testable import MacFindKit

final class QueryParserTests: XCTestCase {

    func testLiteral() throws {
        let q = try SearchQuery.parse("report")
        XCTAssertEqual(q.literals, ["report"])
        XCTAssertTrue(q.excludedLiterals.isEmpty)
    }

    func testMultipleLiteralsAndNegation() throws {
        let q = try SearchQuery.parse("report !tmp -draft")
        XCTAssertEqual(q.literals, ["report"])
        XCTAssertEqual(q.excludedLiterals, ["tmp", "draft"])
    }

    func testExtensions() throws {
        let q = try SearchQuery.parse("ext:pdf,epub")
        XCTAssertEqual(q.extensions, ["pdf", "epub"])
    }

    func testExcludedExtensions() throws {
        let q = try SearchQuery.parse("!ext:tmp")
        XCTAssertEqual(q.excludedExtensions, ["tmp"])
        XCTAssertTrue(q.extensions.isEmpty)
    }

    func testSizeOperatorsAndSuffixes() throws {
        let q = try SearchQuery.parse("size:>10M size:<=1K size:2G")
        XCTAssertEqual(q.sizes, [
            SizeConstraint(op: .gt, bytes: 10 * 1024 * 1024),
            SizeConstraint(op: .le, bytes: 1024),
            SizeConstraint(op: .ge, bytes: 2 * 1024 * 1024 * 1024),
        ])
    }

    func testInvalidSizeThrows() {
        XCTAssertThrowsError(try SearchQuery.parse("size:>abc"))
    }

    /// 回归:大数值 × 单位后缀曾触发 Int64 乘法溢出崩溃(trap),必须抛错而非崩溃。
    func testSizeOverflowThrowsInsteadOfCrashing() {
        XCTAssertThrowsError(try SearchQuery.parse("size:>9000000000G")) { err in
            XCTAssertEqual(err as? QueryParseError, .invalidSize(">9000000000G"))
        }
        XCTAssertThrowsError(try SearchQuery.parse("size:99999999999999M"))
        XCTAssertNoThrow(try SearchQuery.parse("size:>8G"))   // 边界内仍可用
    }

    /// 错误信息必须可读(状态栏要展示)。
    func testParseErrorMessagesAreDescriptive() {
        XCTAssertTrue(QueryParseError.invalidSize("x").errorDescription?.contains("size:") == true)
        XCTAssertTrue(QueryParseError.invalidDate("x").errorDescription?.contains("date:") == true)
        XCTAssertNotNil(QueryParseError.unterminatedQuote.errorDescription)
    }

    /// `in:` 目录校验:存在为 nil,不存在返回错误文案。
    func testScopeValidation() throws {
        let ok = try SearchQuery.parse("in:/Applications")
        XCTAssertNil(ok.scopeValidationError())

        let bad = try SearchQuery.parse("in:/definitely/not/here")
        XCTAssertNotNil(bad.scopeValidationError())

        let none = try SearchQuery.parse("report")
        XCTAssertNil(none.scopeValidationError())   // 无 scope 不报错
    }

    func testRelativeDate() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let q = try SearchQuery.parse("date:7d", now: now)
        let expected = Calendar.current.date(byAdding: .day, value: -7, to: now)
        XCTAssertEqual(q.modifiedAfter, expected)
    }

    func testTodayDate() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let q = try SearchQuery.parse("date:today", now: now)
        XCTAssertEqual(q.modifiedAfter, Calendar.current.startOfDay(for: now))
    }

    func testAbsoluteDate() throws {
        let q = try SearchQuery.parse("date:>2024-01-01")
        XCTAssertNotNil(q.modifiedAfter)
        let comps = Calendar.current.dateComponents([.year, .month, .day], from: q.modifiedAfter!)
        XCTAssertEqual(comps.year, 2024)
        XCTAssertEqual(comps.month, 1)
        XCTAssertEqual(comps.day, 1)
    }

    func testKind() throws {
        let q = try SearchQuery.parse("kind:dir kind:file")
        XCTAssertEqual(q.kinds, [.dir, .file])
    }

    func testInScopeExpandsTilde() throws {
        let q = try SearchQuery.parse("in:~/Downloads")
        XCTAssertEqual(q.scope, (("~/Downloads") as NSString).expandingTildeInPath)
        XCTAssertTrue(q.scope!.hasPrefix("/"))
    }

    func testNameFilterTreatedAsLiteral() throws {
        let q = try SearchQuery.parse("name:config")
        XCTAssertEqual(q.literals, ["config"])
    }

    func testQuotedString() throws {
        let q = try SearchQuery.parse("\"my report\"")
        XCTAssertEqual(q.literals, ["my report"])
    }

    func testUnterminatedQuoteThrows() {
        XCTAssertThrowsError(try SearchQuery.parse("\"oops")) { err in
            XCTAssertEqual(err as? QueryParseError, .unterminatedQuote)
        }
    }

    func testEmptyQueryHasNilPredicate() throws {
        let q = try SearchQuery.parse("")
        XCTAssertTrue(q.isEmpty)
        XCTAssertNil(q.predicate())
    }

    func testCombinedQueryBuildsPredicate() throws {
        let q = try SearchQuery.parse("report ext:pdf size:>5M !path:node_modules kind:file")
        XCTAssertNotNil(q.predicate())
        XCTAssertEqual(q.literals, ["report"])
        XCTAssertEqual(q.extensions, ["pdf"])
        XCTAssertEqual(q.sizes, [SizeConstraint(op: .gt, bytes: 5 * 1024 * 1024)])
        XCTAssertEqual(q.kinds, [.file])
    }
}
