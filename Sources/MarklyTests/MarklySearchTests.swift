//
//  MarklySearchTests.swift
//  Markly
//
//  Verifies the pure in-document search domain: matching (heading/paragraph/code/HTML), section
//  scoping (enclosing heading + front-matter), recursion into block quotes/lists/tables,
//  case sensitivity, whole-word matching, snippet windowing + match range, and Codable
//  round-trip. No I/O, no SwiftUI — runs anywhere.
//

import Testing
import Foundation
@testable import Markly

@Suite struct MarklySearchTests {

    private func parse(_ source: String) -> [MarklyBlock] {
        MarklyDocumentParser.parse(source)
    }

    // MARK: - Empty / whitespace query

    @Test func emptyQueryReturnsNoResults() {
        #expect(MarklySearch.results(for: "", in: parse("# Hi")).isEmpty)
    }

    @Test func whitespaceQueryReturnsNoResults() {
        #expect(MarklySearch.results(for: "   ", in: parse("# Hi")).isEmpty)
    }

    // MARK: - Matching across block types

    @Test func matchesHeadingTextCaseInsensitive() {
        let blocks = parse("# Introduction to Markly")
        let results = MarklySearch.results(for: "markly", in: blocks)
        #expect(results.count == 1)
        #expect(results.first?.blockID.raw == blocks.first?.id.raw)
        #expect(results.first?.sectionTitle == "Introduction to Markly")
    }

    @Test func matchesParagraphText() {
        let blocks = parse("# Title\n\nA paragraph about **bold** content here.")
        let results = MarklySearch.results(for: "bold", in: blocks)
        #expect(results.count == 1)
        #expect(results.first?.sectionTitle == "Title")
    }

    @Test func matchesCodeBlockRawCode() {
        let blocks = parse("```swift\nlet secret = 42\n```")
        let results = MarklySearch.results(for: "secret", in: blocks)
        #expect(results.count == 1, "codeBlock.code must be scanned directly")
    }

    @Test func matchesHTMLBlockRawHTML() {
        let blocks = parse("<div class=\"banner\">hi</div>")
        let results = MarklySearch.results(for: "banner", in: blocks)
        #expect(results.count == 1, "htmlBlock raw HTML must be scanned directly")
    }

    @Test func matchesTableCells() {
        let blocks = parse("| Name | Role |\n|:--|:--|\n| Ada | engineer |\n| Lin | analyst |")
        let results = MarklySearch.results(for: "analyst", in: blocks)
        #expect(results.count == 1)
    }

    // MARK: - Section scoping

    @Test func resultCarriesEnclosingSection() {
        let blocks = parse("# Chapter One\n\nSome intro text.\n\n## Section A\n\nMatching text here.")
        let results = MarklySearch.results(for: "matching", in: blocks)
        #expect(results.count == 1)
        #expect(results.first?.sectionTitle == "Section A")
        #expect(results.first?.sectionID.raw == "h2-section-a")
    }

    @Test func frontMatterBeforeFirstHeadingUsesSyntheticSection() {
        let blocks = parse("Preamble text matching.\n\n# Heading")
        let results = MarklySearch.results(for: "preamble", in: blocks)
        #expect(results.count == 1)
        #expect(results.first?.sectionTitle == MarklySearch.startOfDocumentTitle)
        // Front matter scrolls to the matched block itself (no heading yet).
        #expect(results.first?.sectionID.raw == results.first?.blockID.raw)
    }

    @Test func recursesIntoBlockQuote() {
        let blocks = parse("# H\n\n> A nested quote with needle.")
        let results = MarklySearch.results(for: "needle", in: blocks)
        #expect(results.count == 1)
        #expect(results.first?.sectionTitle == "H")
    }

    @Test func recursesIntoListItems() {
        let blocks = parse("# H\n\n- item with needle\n- other")
        let results = MarklySearch.results(for: "needle", in: blocks)
        #expect(results.count == 1)
    }

    // MARK: - Case sensitivity + whole word

    @Test func caseSensitivity() {
        let blocks = parse("# Swift\n\nswift SWIFT")
        let insensitive = MarklySearch.results(for: "swift", in: blocks, options: .init(caseSensitive: false))
        let sensitive = MarklySearch.results(for: "swift", in: blocks, options: .init(caseSensitive: true))
        // Case-insensitive finds both the heading "Swift" and the two paragraph occurrences;
        // case-sensitive finds only the lowercase "swift" in the paragraph.
        #expect(insensitive.count > sensitive.count)
    }

    @Test func wholeWordOption() {
        let blocks = parse("# Title\n\nThe standalone word and the compound worded.")
        let substring = MarklySearch.results(for: "word", in: blocks, options: .init(wholeWord: false))
        let whole = MarklySearch.results(for: "word", in: blocks, options: .init(wholeWord: true))
        // Substring matches both "word" and "worded"; whole-word matches only "word".
        #expect(substring.count > whole.count)
        #expect(whole.count == 1)
    }

    // MARK: - Per-occurrence results

    @Test func multipleOccurrencesInOneBlockProduceMultipleResults() {
        let blocks = parse("# H\n\nfoo foo foo")
        let results = MarklySearch.results(for: "foo", in: blocks)
        #expect(results.count == 3)
        // Each result has a distinct id (block + absolute match offset).
        #expect(Set(results.map(\.id)).count == 3)
    }

    // MARK: - Snippet + match range

    @Test func snippetIsWindowedAndMatchRangeIsWithinSnippet() throws {
        let long = String(repeating: "x", count: 200)
        let text = long + " NEEDLE " + long
        let blocks = parse("# H\n\n\(text)")
        let results = MarklySearch.results(for: "needle", in: blocks)
        #expect(results.count == 1)
        let r = try #require(results.first)
        #expect(r.snippet.count <= 200)
        #expect(r.matchRange.lowerBound >= 0)
        #expect(r.matchRange.upperBound <= r.snippet.count)
        #expect(r.matchRange.lowerBound < r.matchRange.upperBound)
        // The snippet windowed around the match should contain "NEEDLE" at matchRange.
        let snippet = r.snippet
        let lower = snippet.index(snippet.startIndex, offsetBy: r.matchRange.lowerBound)
        let upper = snippet.index(snippet.startIndex, offsetBy: r.matchRange.upperBound)
        #expect(snippet[lower..<upper].lowercased() == "needle")
    }

    @Test func snippetAddsEllipsisWhenTruncated() throws {
        let long = String(repeating: "x", count: 200)
        let text = long + " needle " + long
        let blocks = parse("# H\n\n\(text)")
        let r = try #require(MarklySearch.results(for: "needle", in: blocks).first)
        #expect(r.snippet.hasPrefix("…"), "snippet should start with an ellipsis when truncated before the match")
        #expect(r.snippet.hasSuffix("…"), "snippet should end with an ellipsis when truncated after the match")
    }

    // MARK: - Codable

    @Test func resultIsCodable() throws {
        let blocks = parse("# H\n\nMatch this.")
        let result = try #require(MarklySearch.results(for: "match", in: blocks).first)
        let data = try JSONEncoder().encode([result])
        let decoded = try JSONDecoder().decode([MarklySearchResult].self, from: data)
        #expect(decoded == [result])
    }
}