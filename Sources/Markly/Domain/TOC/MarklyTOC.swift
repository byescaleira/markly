//
//  MarklyTOC.swift
//  Markly
//
//  Pure table-of-contents derivation from the parsed block model. Walks `[MarklyBlock]`
//  (recursing into block quotes, list items, and block directives) and collects every heading
//  as a `MarklyTOCEntry` keyed by its stable `MarklySectionID`. This is independent of Nebula and
//  SwiftUI — unit-testable on its own. The reading surface scrolls to an entry's `id` via
//  `ScrollViewReader` (see MarklyReaderView).
//

import Foundation

/// A table-of-contents entry: a heading's level, plain-text title, and stable section id.
public struct MarklyTOCEntry: Sendable, Equatable, Identifiable {
    /// The stable section id (matches the block's `MarklySectionID`).
    public let id: MarklySectionID
    /// The heading level (1–6).
    public let level: Int
    /// The heading's plain-text title (flattened inlines).
    public let title: String

    /// Creates a TOC entry.
    public init(id: MarklySectionID, level: Int, title: String) {
        self.id = id
        self.level = level
        self.title = title
    }
}

/// Derives a table of contents from parsed blocks.
public enum MarklyTOC {
    /// Extracts all headings from the given blocks, preserving document order, recursing into
    /// block quotes, list items, and block directives.
    public static func entries(from blocks: [MarklyBlock]) -> [MarklyTOCEntry] {
        var out: [MarklyTOCEntry] = []
        for block in blocks {
            collect(block, into: &out)
        }
        return out
    }

    private static func collect(_ block: MarklyBlock, into out: inout [MarklyTOCEntry]) {
        switch block {
        case .heading(let level, let inlines, let id):
            out.append(MarklyTOCEntry(id: id, level: level, title: inlinePlainText(inlines)))
        case .blockQuote(let blocks, _):
            for sub in blocks { collect(sub, into: &out) }
        case .list(_, _, let items, _):
            for itemBlocks in items {
                for sub in itemBlocks { collect(sub, into: &out) }
            }
        case .blockDirective(_, _, let blocks, _):
            for sub in blocks { collect(sub, into: &out) }
        default:
            break
        }
    }
}