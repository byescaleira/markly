//
//  MarklyDocumentParserTests.swift
//  Markly
//
//  Verifies the swift-markdown → Markly block model mapping for the common constructs.
//

import Testing
@testable import Markly

@Suite struct MarklyDocumentParserTests {

    @Test func parsesHeadingAndParagraph() {
        let blocks = MarklyDocumentParser.parse("# Title\n\nPlain paragraph.")
        #expect(blocks.count == 2)

        guard case .heading(let level, let inlines, let id) = blocks[0] else {
            Issue.record("Expected a heading, got \(blocks[0])"); return
        }
        #expect(level == 1)
        #expect(inlines == [.text("Title")])
        #expect(id.raw == "h1-title")

        guard case .paragraph(let paraInlines, _) = blocks[1] else {
            Issue.record("Expected a paragraph, got \(blocks[1])"); return
        }
        #expect(paraInlines == [.text("Plain paragraph.")])
    }

    @Test func parsesInlineStyles() {
        let blocks = MarklyDocumentParser.parse("**bold** *italic* ~~struck~~ `code`")
        guard case .paragraph(let inlines, _) = blocks.first else {
            Issue.record("Expected a paragraph"); return
        }
        #expect(inlines == [
            .strong([.text("bold")]),
            .text(" "),
            .emphasis([.text("italic")]),
            .text(" "),
            .strikethrough([.text("struck")]),
            .text(" "),
            .inlineCode("code")
        ])
    }

    @Test func parsesLinkAndImage() {
        let blocks = MarklyDocumentParser.parse("[label](https://example.com)\n\n![alt](https://example.com/img.png)")
        guard case .paragraph(let first, _) = blocks[0] else { Issue.record("Expected a paragraph"); return }
        #expect(first == [.link(destination: "https://example.com", inlines: [.text("label")])])

        guard case .paragraph(let second, _) = blocks[1] else { Issue.record("Expected a paragraph"); return }
        #expect(second == [.image(source: "https://example.com/img.png", alt: "alt")])
    }

    @Test func parsesCodeBlockWithLanguage() {
        let source = "```swift\nlet x = 1\n```"
        let blocks = MarklyDocumentParser.parse(source)
        guard case .codeBlock(let language, let code, _) = blocks.first else {
            Issue.record("Expected a code block"); return
        }
        #expect(language == "swift")
        #expect(code == "let x = 1\n")
    }

    @Test func parsesOrderedList() {
        let blocks = MarklyDocumentParser.parse("1. first\n2. second")
        guard case .list(let ordered, _, let items, _) = blocks.first else {
            Issue.record("Expected a list"); return
        }
        #expect(ordered)
        #expect(items.count == 2)
        guard case .paragraph(let firstItemInlines, _) = items[0].first else {
            Issue.record("Expected the list item to contain a paragraph"); return
        }
        #expect(firstItemInlines == [.text("first")])
    }

    @Test func parsesTableWithAlignment() {
        let source = "| A | B |\n|:--|:-:|\n| 1 | 2 |"
        let blocks = MarklyDocumentParser.parse(source)
        guard case .table(let header, let rows, _) = blocks.first else {
            Issue.record("Expected a table"); return
        }
        #expect(header.count == 2)
        #expect(header[0].alignment == .left)
        #expect(header[1].alignment == .center)
        #expect(rows.count == 1)
        #expect(rows[0].count == 2)
    }

    @Test func sectionIDsAreStableAcrossRuns() {
        let a = MarklyDocumentParser.parse("# One\n\ntext\n\n# Two")
        let b = MarklyDocumentParser.parse("# One\n\ntext\n\n# Two")
        #expect(a.map(\.id.raw) == b.map(\.id.raw))
        #expect(a.map(\.id.raw) == ["h1-one", "blk-0002", "h1-two"])
    }

    // MARK: - Review-fix regressions

    @Test func duplicateHeadingsGetUniqueSectionIDs() {
        let blocks = MarklyDocumentParser.parse("## Introduction\n\n## Introduction\n\n## Introduction")
        let ids = blocks.map(\.id.raw)
        // First keeps the bare slug; repeats get numeric suffixes so bookmarks/TOC deep-links
        // can target each heading uniquely.
        #expect(ids == ["h2-introduction", "h2-introduction-2", "h2-introduction-3"])
        #expect(Set(ids).count == ids.count, "Section IDs must be unique")
    }

    @Test func parsesBlockDirective() {
        let blocks = MarklyDocumentParser.parse("@note {\nThis is a note.\n}\n")
        guard case .blockDirective(let name, _, let children, _) = blocks.first else {
            Issue.record("Expected a blockDirective, got \(String(describing: blocks.first))"); return
        }
        #expect(name == "note")
        #expect(!children.isEmpty, "Directive children should be parsed, not empty")
    }

    @Test func codeLanguageIsFirstInfoStringToken() {
        let blocks = MarklyDocumentParser.parse("```ruby foo bar\nx\n```")
        guard case .codeBlock(let language, let code, _) = blocks.first else {
            Issue.record("Expected a code block"); return
        }
        // CommonMark: only the first whitespace-separated word is the language.
        #expect(language == "ruby")
        #expect(code == "x\n")
    }

    @Test func inlineSerializerEscapesTilde() {
        // A literal double-tilde in text must not round-trip into GFM strikethrough.
        let markdown = MarklyInlineSerializer.toMarkdown([.text("~~hi~~")])
        #expect(markdown == "\\~\\~hi\\~\\~")
    }

    @Test func inlineSerializerAngleWrapsParenDestinations() {
        // A destination containing ')' must be angle-wrapped or the inline reparse truncates it.
        let markdown = MarklyInlineSerializer.toMarkdown([
            .link(destination: "https://example.com/a)b", inlines: [.text("label")])
        ])
        #expect(markdown == "[label](<https://example.com/a)b>)")
    }

    // MARK: - inlineCode whitespace round-trip

    @Test func inlineCodeWithoutSurroundingSpaceRoundTrips() {
        #expect(MarklyInlineSerializer.toMarkdown([.inlineCode("hi")]) == "`hi`")
    }

    @Test func inlineCodeWithSurroundingSpaceIsPaddedForRoundTrip() {
        // " hi " begins + ends with a space (and is not all whitespace) -> pad one space each side
        // so CommonMark strips the padding, not the model content, on the inline reparse.
        #expect(MarklyInlineSerializer.toMarkdown([.inlineCode(" hi ")]) == "`  hi  `")
    }

    @Test func inlineCodeAllWhitespaceIsNotPadded() {
        #expect(MarklyInlineSerializer.toMarkdown([.inlineCode(" ")]) == "` `")
    }

    @Test func inlineCodeWithPaddingParsesBackToSameContent() {
        let blocks = MarklyDocumentParser.parse("`  hi  `")
        guard case .paragraph(let inlines, _) = blocks.first else {
            Issue.record("Expected a paragraph"); return
        }
        #expect(inlines == [.inlineCode(" hi ")])
    }
}