//
//  MarklyBlockNodeConverterTests.swift
//  Markly
//
//  Verifies the Markly AST → MarkdownUI `BlockNode` / `InlineNode` mapping used to route the leaf
//  blocks (heading, codeBlock, thematicBreak, htmlBlock) through the vendored MarkdownUI
//  renderer. The mapping is 1:1 for the CommonMark/GFM subset Markly models.
//

import Testing
@testable import Markly
import MarkdownUI

@Suite struct MarklyBlockNodeConverterTests {

    // MARK: Inlines

    @Test func convertsLeafInlines() {
        #expect(MarklyBlockNodeConverter.inline(.text("hi")) == .text("hi"))
        #expect(MarklyBlockNodeConverter.inline(.softBreak) == .softBreak)
        #expect(MarklyBlockNodeConverter.inline(.lineBreak) == .lineBreak)
        #expect(MarklyBlockNodeConverter.inline(.inlineCode("x")) == .code("x"))
    }

    @Test func convertsContainerInlines() {
        #expect(MarklyBlockNodeConverter.inline(.strong([.text("b")])) == .strong(children: [.text("b")]))
        #expect(MarklyBlockNodeConverter.inline(.emphasis([.text("i")])) == .emphasis(children: [.text("i")]))
        #expect(
            MarklyBlockNodeConverter.inline(.strikethrough([.text("s")])) == .strikethrough(children: [.text("s")])
        )
    }

    @Test func convertsLinkAndImage() {
        #expect(
            MarklyBlockNodeConverter.inline(.link(destination: "https://a.io", inlines: [.text("A")]))
            == .link(destination: "https://a.io", children: [.text("A")])
        )
        // An image's alt text becomes a child `.text` inline in MarkdownUI's model.
        #expect(
            MarklyBlockNodeConverter.inline(.image(source: "https://a.io/i.png", alt: "alt"))
            == .image(source: "https://a.io/i.png", children: [.text("alt")])
        )
    }

    @Test func convertsInlineList() {
        let inlines: [MarklyInline] = [.text("a"), .softBreak, .text("b")]
        #expect(MarklyBlockNodeConverter.inlines(inlines) == [.text("a"), .softBreak, .text("b")])
    }

    // MARK: Blocks

    @Test func clampsOutOfRangeHeadingLevel() {
        // MarkdownUI's `HeadingView` indexes a 6-element `theme.headings` array, so an out-of-range
        // level would crash. The parser only emits 1...6, but `MarklyBlock.heading` is a
        // programmatic value; the converter clamps to be total (mirroring the accessibility path).
        #expect(
            MarklyBlockNodeConverter.block(.heading(level: 0, inlines: [.text("T")], id: MarklySectionID(raw: "x")))
            == .heading(level: 1, content: [.text("T")])
        )
        #expect(
            MarklyBlockNodeConverter.block(.heading(level: 7, inlines: [.text("T")], id: MarklySectionID(raw: "x")))
            == .heading(level: 6, content: [.text("T")])
        )
        #expect(
            MarklyBlockNodeConverter.block(.heading(level: -3, inlines: [.text("T")], id: MarklySectionID(raw: "x")))
            == .heading(level: 1, content: [.text("T")])
        )
    }

    @Test func convertsHeadingParagraphCodeHtml() {
        #expect(
            MarklyBlockNodeConverter.block(.heading(level: 2, inlines: [.text("T")], id: MarklySectionID(raw: "x")))
            == .heading(level: 2, content: [.text("T")])
        )
        #expect(
            MarklyBlockNodeConverter.block(.paragraph(inlines: [.text("p")], id: MarklySectionID(raw: "x")))
            == .paragraph(content: [.text("p")])
        )
        #expect(
            MarklyBlockNodeConverter.block(.codeBlock(language: "swift", code: "let x = 1", id: MarklySectionID(raw: "x")))
            == .codeBlock(fenceInfo: "swift", content: "let x = 1")
        )
        #expect(
            MarklyBlockNodeConverter.block(.htmlBlock("<b>raw</b>", id: MarklySectionID(raw: "x")))
            == .htmlBlock(content: "<b>raw</b>")
        )
        #expect(MarklyBlockNodeConverter.block(.thematicBreak(id: MarklySectionID(raw: "x"))) == .thematicBreak)
    }

    @Test func convertsBlockQuote() {
        let node = MarklyBlockNodeConverter.block(.blockQuote(blocks: [.paragraph(inlines: [.text("q")], id: MarklySectionID(raw: "x"))], id: MarklySectionID(raw: "x")))
        #expect(node == .blockquote(children: [.paragraph(content: [.text("q")])]))
    }

    @Test func convertsUnorderedAndOrderedList() {
        let item: [MarklyBlock] = [.paragraph(inlines: [.text("a")], id: MarklySectionID(raw: "x"))]
        #expect(
            MarklyBlockNodeConverter.block(.list(ordered: false, start: nil, items: [item], id: MarklySectionID(raw: "x")))
            == .bulletedList(isTight: false, items: [RawListItem(children: [.paragraph(content: [.text("a")])])])
        )
        #expect(
            MarklyBlockNodeConverter.block(.list(ordered: true, start: 3, items: [item], id: MarklySectionID(raw: "x")))
            == .numberedList(isTight: false, start: 3, items: [RawListItem(children: [.paragraph(content: [.text("a")])])])
        )
        // `start` defaults to 1 when nil for ordered lists.
        #expect(
            MarklyBlockNodeConverter.block(.list(ordered: true, start: nil, items: [item], id: MarklySectionID(raw: "x")))
            == .numberedList(isTight: false, start: 1, items: [RawListItem(children: [.paragraph(content: [.text("a")])])])
        )
    }

    @Test func convertsTableWithAlignments() {
        let header: [MarklyTableCell] = [
            .init(inlines: [.text("A")], alignment: .left),
            .init(inlines: [.text("B")], alignment: .center),
            .init(inlines: [.text("C")], alignment: .right),
            .init(inlines: [.text("D")], alignment: nil),
        ]
        let row: [MarklyTableCell] = [.init(inlines: [.text("1")], alignment: nil)]
        let node = MarklyBlockNodeConverter.block(.table(header: header, rows: [row], id: MarklySectionID(raw: "x")))

        #expect(node == .table(
            columnAlignments: [.left, .center, .right, .none],
            rows: [
                RawTableRow(cells: [
                    RawTableCell(content: [.text("A")]),
                    RawTableCell(content: [.text("B")]),
                    RawTableCell(content: [.text("C")]),
                    RawTableCell(content: [.text("D")]),
                ]),
                RawTableRow(cells: [RawTableCell(content: [.text("1")])]),
            ]
        ))
    }

    @Test func convertsBlockDirectiveAsBlockquoteFallback() {
        // No MarkdownUI equivalent; the converter falls back to a blockquote of the children. This
        // case is never reached on the rendered path (blockDirective stays on Markly's renderer).
        let node = MarklyBlockNodeConverter.block(
            .blockDirective(name: "note", arguments: "", blocks: [.paragraph(inlines: [.text("n")], id: MarklySectionID(raw: "x"))], id: MarklySectionID(raw: "x"))
        )
        #expect(node == .blockquote(children: [.paragraph(content: [.text("n")])]))
    }
}