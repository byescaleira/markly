//
//  MarklyBlockNodeConverter.swift
//
//  Bridges Markly's `MarklyBlock` / `MarklyInline` AST (parsed once with Apple's
//  `apple/swift-markdown`) into MarkdownUI's `BlockNode` / `InlineNode` AST, so Markly can render
//  the non-paragraph blocks through MarkdownUI's vendored block views (headings, code blocks,
//  thematic breaks, HTML blocks). The mapping is 1:1 for the CommonMark/GFM subset Markly models.
//
//  Scope: Markly routes only leaf blocks with no nested *selectable* paragraphs — heading,
//  codeBlock, thematicBreak, htmlBlock — through MarkdownUI. Paragraph, blockQuote, list, table,
//  and blockDirective stay on Markly's own renderer so that selectable-text highlights (whose
//  ranges are a byte-for-byte round trip through `MarklyInlineSerializer` + Foundation) keep
//  working at every nesting level. This converter is nonetheless total over `MarklyBlock` so it
//  can be unit-tested and can power a future "pure MarkdownUI" render mode; the `blockDirective`
//  case (which has no MarkdownUI equivalent) falls back to a `blockquote` of its children and is
//  never reached on the rendered path. See docs/Architecture.md §3, §10.
//

import Foundation
import MarkdownUI

/// Converts Markly's AST into MarkdownUI's `BlockNode` / `InlineNode` AST.
enum MarklyBlockNodeConverter {

    /// Converts a Markly inline run into a MarkdownUI inline node.
    static func inline(_ node: MarklyInline) -> InlineNode {
        switch node {
        case .text(let string):
            return .text(string)
        case .softBreak:
            return .softBreak
        case .lineBreak:
            return .lineBreak
        case .strong(let children):
            return .strong(children: children.map { inline($0) })
        case .emphasis(let children):
            return .emphasis(children: children.map { inline($0) })
        case .strikethrough(let children):
            return .strikethrough(children: children.map { inline($0) })
        case .inlineCode(let string):
            return .code(string)
        case .link(let destination, let inlines):
            return .link(destination: destination, children: inlines.map { inline($0) })
        case .image(let source, let alt):
            // MarkdownUI models an image's alt text as a child `.text` inline.
            return .image(source: source, children: [.text(alt)])
        }
    }

    /// Converts a list of Markly inlines into MarkdownUI inline nodes.
    static func inlines(_ inlines: [MarklyInline]) -> [InlineNode] {
        inlines.map { inline($0) }
    }

    /// Converts a Markly block into a MarkdownUI block node.
    static func block(_ node: MarklyBlock) -> BlockNode {
        switch node {
        case .heading(let level, let inlines, _):
            // MarkdownUI's `HeadingView` indexes `theme.headings[level - 1]` (a 6-element
            // array), so a level outside 1...6 crashes with index-out-of-range. The parser only
            // emits 1...6, but `MarklyBlock.heading` is a programmatic domain value; clamp to be
            // total. This mirrors `MarklyBlockView.accessibilityHeadingLevel`, which already
            // folds any out-of-range level onto `.h6`.
            let clamped = min(max(level, 1), 6)
            return .heading(level: clamped, content: inlines.map { inline($0) })

        case .paragraph(let inlines, _):
            return .paragraph(content: inlines.map { inline($0) })

        case .codeBlock(let language, let code, _):
            return .codeBlock(fenceInfo: language, content: code)

        case .blockQuote(let blocks, _):
            return .blockquote(children: blocks.map { block($0) })

        case .list(let ordered, let start, let items, _):
            let rawItems = items.map { RawListItem(children: $0.map { block($0) }) }
            if ordered {
                return .numberedList(isTight: false, start: start ?? 1, items: rawItems)
            } else {
                return .bulletedList(isTight: false, items: rawItems)
            }

        case .thematicBreak:
            return .thematicBreak

        case .table(let header, let rows, _):
            let alignments = header.map { RawTableColumnAlignment($0.alignment) }
            var tableRows: [RawTableRow] = [RawTableRow(cells: header.map { tableCell($0) })]
            tableRows.append(contentsOf: rows.map { RawTableRow(cells: $0.map { tableCell($0) }) })
            return .table(columnAlignments: alignments, rows: tableRows)

        case .htmlBlock(let html, _):
            return .htmlBlock(content: html)

        case .blockDirective(_, _, let blocks, _):
            // No MarkdownUI equivalent; fall back to a blockquote of the children. Never reached
            // on the rendered path — `blockDirective` stays on Markly's own renderer.
            return .blockquote(children: blocks.map { block($0) })
        }
    }

    /// Converts a Markly table cell into a MarkdownUI raw table cell.
    static func tableCell(_ cell: MarklyTableCell) -> RawTableCell {
        RawTableCell(content: cell.inlines.map { inline($0) })
    }
}

private extension RawTableColumnAlignment {
    /// Maps a Markly column alignment (optional) into MarkdownUI's raw alignment enum.
    init(_ alignment: MarklyColumnAlignment?) {
        switch alignment {
        case .left: self = .left
        case .center: self = .center
        case .right: self = .right
        case .none: self = .none
        }
    }
}