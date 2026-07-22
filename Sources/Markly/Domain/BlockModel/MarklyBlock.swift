//
//  MarklyBlock.swift
//  Markly
//
//  The pure block model — the contract between the parser and the renderer. Parsed once per
//  document from swift-markdown's `Document`, cached, and rendered block-by-block. It is
//  `Sendable` (trivially cacheable/shareable across actors) and `Codable` (enables reading-
//  state snapshots and deep-link restoration). Block layout is owned by Markly's renderer;
//  Apple sanctions no SwiftUI block-markdown view (see docs/Architecture.md §3, §10).
//

import Foundation

/// A single block-level markdown construct, modeled as a recursive value type.
public enum MarklyBlock: Sendable, Equatable, Codable {
    /// A heading at `level` (1–6) with inline content.
    case heading(level: Int, inlines: [MarklyInline], id: MarklySectionID)
    /// A paragraph of inline content.
    case paragraph(inlines: [MarklyInline], id: MarklySectionID)
    /// A fenced or indented code block, optionally with a language info string.
    case codeBlock(language: String?, code: String, id: MarklySectionID)
    /// A block quote containing nested blocks.
    case blockQuote(blocks: [MarklyBlock], id: MarklySectionID)
    /// A list; `ordered` distinguishes ordered from bullet lists, `items` are each a list of
    /// nested blocks (a list item's content).
    case list(ordered: Bool, start: Int?, items: [[MarklyBlock]], id: MarklySectionID)
    /// A thematic break (horizontal rule).
    case thematicBreak(id: MarklySectionID)
    /// A table with a header row and body rows.
    case table(header: [MarklyTableCell], rows: [[MarklyTableCell]], id: MarklySectionID)
    /// A raw HTML block, rendered verbatim (no inline HTML rendering — see docs/Architecture.md §10).
    case htmlBlock(String, id: MarklySectionID)
    /// A block directive (e.g. a custom admonition) containing nested blocks.
    case blockDirective(name: String, arguments: String, blocks: [MarklyBlock], id: MarklySectionID)

    /// The stable identity of this block (used for scroll anchors, bookmarks, TOC deep-links).
    public var id: MarklySectionID {
        switch self {
        case .heading(_, _, let id): return id
        case .paragraph(_, let id): return id
        case .codeBlock(_, _, let id): return id
        case .blockQuote(_, let id): return id
        case .list(_, _, _, let id): return id
        case .thematicBreak(let id): return id
        case .table(_, _, let id): return id
        case .htmlBlock(_, let id): return id
        case .blockDirective(_, _, _, let id): return id
        }
    }
}