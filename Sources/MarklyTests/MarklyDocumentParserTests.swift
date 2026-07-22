//
//  MarklyDocumentParserTests.swift
//  Markly
//
//  Verifies the swift-markdown → Markly block model mapping for the common constructs.
//

import XCTest
@testable import Markly

final class MarklyDocumentParserTests: XCTestCase {

    func testParsesHeadingAndParagraph() {
        let blocks = MarklyDocumentParser.parse("# Title\n\nPlain paragraph.")
        XCTAssertEqual(blocks.count, 2)

        guard case .heading(let level, let inlines, let id) = blocks[0] else {
            return XCTFail("Expected a heading, got \(blocks[0])")
        }
        XCTAssertEqual(level, 1)
        XCTAssertEqual(inlines, [.text("Title")])
        XCTAssertEqual(id.raw, "h1-title")

        guard case .paragraph(let paraInlines, _) = blocks[1] else {
            return XCTFail("Expected a paragraph, got \(blocks[1])")
        }
        XCTAssertEqual(paraInlines, [.text("Plain paragraph.")])
    }

    func testParsesInlineStyles() {
        let blocks = MarklyDocumentParser.parse("**bold** *italic* ~~struck~~ `code`")
        guard case .paragraph(let inlines, _) = blocks.first else {
            return XCTFail("Expected a paragraph")
        }
        XCTAssertEqual(inlines, [
            .strong([.text("bold")]),
            .text(" "),
            .emphasis([.text("italic")]),
            .text(" "),
            .strikethrough([.text("struck")]),
            .text(" "),
            .inlineCode("code")
        ])
    }

    func testParsesLinkAndImage() {
        let blocks = MarklyDocumentParser.parse("[label](https://example.com)\n\n![alt](https://example.com/img.png)")
        guard case .paragraph(let first, _) = blocks[0] else { return XCTFail() }
        XCTAssertEqual(first, [.link(destination: "https://example.com", inlines: [.text("label")])])

        guard case .paragraph(let second, _) = blocks[1] else { return XCTFail() }
        XCTAssertEqual(second, [.image(source: "https://example.com/img.png", alt: "alt")])
    }

    func testParsesCodeBlockWithLanguage() {
        let source = "```swift\nlet x = 1\n```"
        let blocks = MarklyDocumentParser.parse(source)
        guard case .codeBlock(let language, let code, _) = blocks.first else {
            return XCTFail("Expected a code block")
        }
        XCTAssertEqual(language, "swift")
        XCTAssertEqual(code, "let x = 1\n")
    }

    func testParsesOrderedList() {
        let blocks = MarklyDocumentParser.parse("1. first\n2. second")
        guard case .list(let ordered, _, let items, _) = blocks.first else {
            return XCTFail("Expected a list")
        }
        XCTAssertTrue(ordered)
        XCTAssertEqual(items.count, 2)
        guard case .paragraph(let firstItemInlines, _) = items[0].first else {
            return XCTFail("Expected the list item to contain a paragraph")
        }
        XCTAssertEqual(firstItemInlines, [.text("first")])
    }

    func testParsesTableWithAlignment() {
        let source = "| A | B |\n|:--|:-:|\n| 1 | 2 |"
        let blocks = MarklyDocumentParser.parse(source)
        guard case .table(let header, let rows, _) = blocks.first else {
            return XCTFail("Expected a table")
        }
        XCTAssertEqual(header.count, 2)
        XCTAssertEqual(header[0].alignment, .left)
        XCTAssertEqual(header[1].alignment, .center)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].count, 2)
    }

    func testSectionIDsAreStableAcrossRuns() {
        let a = MarklyDocumentParser.parse("# One\n\ntext\n\n# Two")
        let b = MarklyDocumentParser.parse("# One\n\ntext\n\n# Two")
        XCTAssertEqual(a.map(\.id.raw), b.map(\.id.raw))
        XCTAssertEqual(a.map(\.id.raw), ["h1-one", "blk-0002", "h1-two"])
    }

    // MARK: - Review-fix regressions

    func testDuplicateHeadingsGetUniqueSectionIDs() {
        let blocks = MarklyDocumentParser.parse("## Introduction\n\n## Introduction\n\n## Introduction")
        let ids = blocks.map(\.id.raw)
        // First keeps the bare slug; repeats get numeric suffixes so bookmarks/TOC deep-links
        // can target each heading uniquely.
        XCTAssertEqual(ids, ["h2-introduction", "h2-introduction-2", "h2-introduction-3"])
        XCTAssertEqual(Set(ids).count, ids.count, "Section IDs must be unique")
    }

    func testParsesBlockDirective() {
        let blocks = MarklyDocumentParser.parse("@note {\nThis is a note.\n}\n")
        guard case .blockDirective(let name, _, let children, _) = blocks.first else {
            return XCTFail("Expected a blockDirective, got \(String(describing: blocks.first))")
        }
        XCTAssertEqual(name, "note")
        XCTAssertFalse(children.isEmpty, "Directive children should be parsed, not empty")
    }

    func testCodeLanguageIsFirstInfoStringToken() {
        let blocks = MarklyDocumentParser.parse("```ruby foo bar\nx\n```")
        guard case .codeBlock(let language, let code, _) = blocks.first else {
            return XCTFail("Expected a code block")
        }
        // CommonMark: only the first whitespace-separated word is the language.
        XCTAssertEqual(language, "ruby")
        XCTAssertEqual(code, "x\n")
    }

    func testInlineSerializerEscapesTilde() {
        // A literal double-tilde in text must not round-trip into GFM strikethrough.
        let markdown = MarklyInlineSerializer.toMarkdown([.text("~~hi~~")])
        XCTAssertEqual(markdown, "\\~\\~hi\\~\\~")
    }

    func testInlineSerializerAngleWrapsParenDestinations() {
        // A destination containing ')' must be angle-wrapped or the inline reparse truncates it.
        let markdown = MarklyInlineSerializer.toMarkdown([
            .link(destination: "https://example.com/a)b", inlines: [.text("label")])
        ])
        XCTAssertEqual(markdown, "[label](<https://example.com/a)b>)")
    }
}