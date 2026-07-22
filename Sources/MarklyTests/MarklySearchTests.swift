//
//  MarklySearchTests.swift
//  Markly
//
//  Verifies the pure in-document search domain: matching (heading/paragraph/code/HTML), section
//  scoping (enclosing heading + front-matter), recursion into block quotes/lists/tables,
//  case sensitivity, whole-word matching, snippet windowing + match range, and Codable
//  round-trip. No I/O, no SwiftUI — runs anywhere.
//

import XCTest
@testable import Markly

final class MarklySearchTests: XCTestCase {

    private func parse(_ source: String) -> [MarklyBlock] {
        MarklyDocumentParser.parse(source)
    }

    // MARK: - Empty / whitespace query

    func testEmptyQueryReturnsNoResults() {
        XCTAssertTrue(MarklySearch.results(for: "", in: parse("# Hi")).isEmpty)
    }

    func testWhitespaceQueryReturnsNoResults() {
        XCTAssertTrue(MarklySearch.results(for: "   ", in: parse("# Hi")).isEmpty)
    }

    // MARK: - Matching across block types

    func testMatchesHeadingTextCaseInsensitive() {
        let blocks = parse("# Introduction to Markly")
        let results = MarklySearch.results(for: "markly", in: blocks)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.blockID.raw, blocks.first?.id.raw)
        XCTAssertEqual(results.first?.sectionTitle, "Introduction to Markly")
    }

    func testMatchesParagraphText() {
        let blocks = parse("# Title\n\nA paragraph about **bold** content here.")
        let results = MarklySearch.results(for: "bold", in: blocks)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.sectionTitle, "Title")
    }

    func testMatchesCodeBlockRawCode() {
        let blocks = parse("```swift\nlet secret = 42\n```")
        let results = MarklySearch.results(for: "secret", in: blocks)
        XCTAssertEqual(results.count, 1, "codeBlock.code must be scanned directly")
    }

    func testMatchesHTMLBlockRawHTML() {
        let blocks = parse("<div class=\"banner\">hi</div>")
        let results = MarklySearch.results(for: "banner", in: blocks)
        XCTAssertEqual(results.count, 1, "htmlBlock raw HTML must be scanned directly")
    }

    func testMatchesTableCells() {
        let blocks = parse("| Name | Role |\n|:--|:--|\n| Ada | engineer |\n| Lin | analyst |")
        let results = MarklySearch.results(for: "analyst", in: blocks)
        XCTAssertEqual(results.count, 1)
    }

    // MARK: - Section scoping

    func testResultCarriesEnclosingSection() {
        let blocks = parse("# Chapter One\n\nSome intro text.\n\n## Section A\n\nMatching text here.")
        let results = MarklySearch.results(for: "matching", in: blocks)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.sectionTitle, "Section A")
        XCTAssertEqual(results.first?.sectionID.raw, "h2-section-a")
    }

    func testFrontMatterBeforeFirstHeadingUsesSyntheticSection() {
        let blocks = parse("Preamble text matching.\n\n# Heading")
        let results = MarklySearch.results(for: "preamble", in: blocks)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.sectionTitle, MarklySearch.startOfDocumentTitle)
        // Front matter scrolls to the matched block itself (no heading yet).
        XCTAssertEqual(results.first?.sectionID.raw, results.first?.blockID.raw)
    }

    func testRecursesIntoBlockQuote() {
        let blocks = parse("# H\n\n> A nested quote with needle.")
        let results = MarklySearch.results(for: "needle", in: blocks)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.sectionTitle, "H")
    }

    func testRecursesIntoListItems() {
        let blocks = parse("# H\n\n- item with needle\n- other")
        let results = MarklySearch.results(for: "needle", in: blocks)
        XCTAssertEqual(results.count, 1)
    }

    // MARK: - Case sensitivity + whole word

    func testCaseSensitivity() {
        let blocks = parse("# Swift\n\nswift SWIFT")
               let insensitive = MarklySearch.results(for: "swift", in: blocks, options: .init(caseSensitive: false))
        let sensitive = MarklySearch.results(for: "swift", in: blocks, options: .init(caseSensitive: true))
        // Case-insensitive finds both the heading "Swift" and the two paragraph occurrences;
        // case-sensitive finds only the lowercase "swift" in the paragraph.
        XCTAssertGreaterThan(insensitive.count, sensitive.count)
    }

    func testWholeWordOption() {
        let blocks = parse("# Title\n\nThe standalone word and the compound worded.")
               let substring = MarklySearch.results(for: "word", in: blocks, options: .init(wholeWord: false))
        let whole = MarklySearch.results(for: "word", in: blocks, options: .init(wholeWord: true))
        // Substring matches both "word" and "worded"; whole-word matches only "word".
        XCTAssertGreaterThan(substring.count, whole.count)
        XCTAssertEqual(whole.count, 1)
    }

    // MARK: - Per-occurrence results

    func testMultipleOccurrencesInOneBlockProduceMultipleResults() {
        let blocks = parse("# H\n\nfoo foo foo")
        let results = MarklySearch.results(for: "foo", in: blocks)
        XCTAssertEqual(results.count, 3)
        // Each result has a distinct id (block + absolute match offset).
        XCTAssertEqual(Set(results.map(\.id)).count, 3)
    }

    // MARK: - Snippet + match range

    func testSnippetIsWindowedAndMatchRangeIsWithinSnippet() throws {
        let long = String(repeating: "x", count: 200)
        let text = long + " NEEDLE " + long
        let blocks = parse("# H\n\n\(text)")
        let results = MarklySearch.results(for: "needle", in: blocks)
        XCTAssertEqual(results.count, 1)
        let r = try XCTUnwrap(results.first)
        XCTAssertLessThanOrEqual(r.snippet.count, 200)
        XCTAssertGreaterThanOrEqual(r.matchRange.lowerBound, 0)
        XCTAssertLessThanOrEqual(r.matchRange.upperBound, r.snippet.count)
        XCTAssertLessThan(r.matchRange.lowerBound, r.matchRange.upperBound)
        // The snippet windowed around the match should contain "NEEDLE" at matchRange.
        let snippet = r.snippet
        let lower = snippet.index(snippet.startIndex, offsetBy: r.matchRange.lowerBound)
        let upper = snippet.index(snippet.startIndex, offsetBy: r.matchRange.upperBound)
        XCTAssertEqual(snippet[lower..<upper].lowercased(), "needle")
    }

    func testSnippetAddsEllipsisWhenTruncated() throws {
        let long = String(repeating: "x", count: 200)
        let text = long + " needle " + long
        let blocks = parse("# H\n\n\(text)")
        let r = try XCTUnwrap(MarklySearch.results(for: "needle", in: blocks).first)
        XCTAssertTrue(r.snippet.hasPrefix("…"), "snippet should start with an ellipsis when truncated before the match")
        XCTAssertTrue(r.snippet.hasSuffix("…"), "snippet should end with an ellipsis when truncated after the match")
    }

    // MARK: - Codable

    func testResultIsCodable() throws {
        let blocks = parse("# H\n\nMatch this.")
        let result = try XCTUnwrap(MarklySearch.results(for: "match", in: blocks).first)
        let data = try JSONEncoder().encode([result])
        let decoded = try JSONDecoder().decode([MarklySearchResult].self, from: data)
        XCTAssertEqual(decoded, [result])
    }
}