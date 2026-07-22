//
//  MarklyDocumentParser.swift
//  Markly
//
//  Stage 1–2 of the parse → render pipeline (see docs/Architecture.md §3):
//    1. Parse the source once into swift-markdown's `Document` (Apple's official parser).
//    2. Walk the `Document` into Markly's own pure `[MarklyBlock]` block model.
//
//  The block model is the cached render input; the renderer never re-walks the AST on scroll.
//  IDs are derived deterministically from document structure so `ScrollPosition` restore,
//  bookmarks, and TOC deep-links survive re-layout.
//

import Foundation
import Markdown

/// Parses a markdown `String` (or a swift-markdown `Document`) into Markly's pure block model.
public enum MarklyDocumentParser {

    /// Parses a markdown source string into a list of blocks. Block directives
    /// (`@note { … }`, …) are parsed because `ParseOptions.parseBlockDirectives` is on — without
    /// it, swift-markdown emits them as plain paragraphs and the `.blockDirective` model case is
    /// unreachable. (Symbol-link parsing is left off for now; opt in when DocC links are needed.)
    public static func parse(_ source: String) -> [MarklyBlock] {
        parse(Document(parsing: source, options: .parseBlockDirectives))
    }

    /// Parses an already-built swift-markdown `Document` into a list of blocks.
    public static func parse(_ document: Document) -> [MarklyBlock] {
        var ids = SectionIDGenerator()
        return Builder.parseBlocks(document.children, ids: &ids)
    }
}

// MARK: - ID generation

/// Deterministic generator for `MarklySectionID`s. Headings receive a human-readable slug
/// hint (`h2-introduction`); all other blocks receive a stable index (`blk-0042`). Heading hints
/// are de-duplicated: the first occurrence keeps the bare slug, and repeats get a numeric suffix
/// (`h2-introduction-2`, `-3`, …) so every heading — including identically-worded ones — has a
/// unique identity for scroll-restore, bookmarks, and TOC deep-links.
fileprivate struct SectionIDGenerator {
    private var counter = 0
    private var usedHints: Set<String> = []

    mutating func next(_ hint: String? = nil) -> MarklySectionID {
        counter += 1
        if let hint, !hint.isEmpty {
            var raw = hint
            var suffix = 2
            while usedHints.contains(raw) {
                raw = "\(hint)-\(suffix)"
                suffix += 1
            }
            usedHints.insert(raw)
            return MarklySectionID(raw: raw)
        }
        return MarklySectionID(raw: "blk-\(String(format: "%04d", counter))")
    }
}

// MARK: - Block builder

/// Walks swift-markdown block nodes into `MarklyBlock`s. Internal — the public entry point is
/// `MarklyDocumentParser`.
fileprivate enum Builder {
    static func parseBlocks(
        _ children: MarkupChildren,
        ids: inout SectionIDGenerator
    ) -> [MarklyBlock] {
        var blocks: [MarklyBlock] = []
        for child in children {
            if let block = parseBlock(child, ids: &ids) {
                blocks.append(block)
            }
        }
        return blocks
    }

    static func parseBlock(
        _ node: Markup,
        ids: inout SectionIDGenerator
    ) -> MarklyBlock? {
        switch node {
        case let heading as Heading:
            let inlines = InlineCollector.collect(heading.children)
            return .heading(
                level: heading.level,
                inlines: inlines,
                id: ids.next(headingHint(heading.level, inlines))
            )

        case let paragraph as Paragraph:
            return .paragraph(inlines: InlineCollector.collect(paragraph.children), id: ids.next())

        case let code as CodeBlock:
            // CommonMark: the first whitespace-separated word of the fence info string is the
            // language; the rest is metadata. `code.language` returns the *full* info string, so
            // take only the first token so a highlighter/keyed consumer matches cleanly.
            let language = code.language?.split(whereSeparator: { $0.isWhitespace }).first.map(String.init)
            return .codeBlock(language: language, code: code.code, id: ids.next())

        case let quote as BlockQuote:
            return .blockQuote(blocks: parseBlocks(quote.children, ids: &ids), id: ids.next())

        case let list as OrderedList:
            var items: [[MarklyBlock]] = []
            for item in list.listItems {
                items.append(parseBlocks(item.children, ids: &ids))
            }
            return .list(ordered: true, start: Int(list.startIndex), items: items, id: ids.next())

        case let list as UnorderedList:
            var items: [[MarklyBlock]] = []
            for item in list.listItems {
                items.append(parseBlocks(item.children, ids: &ids))
            }
            return .list(ordered: false, start: nil, items: items, id: ids.next())

        case is ThematicBreak:
            return .thematicBreak(id: ids.next())

        case let table as Table:
            return parseTable(table, ids: &ids)

        case let html as HTMLBlock:
            return .htmlBlock(html.rawHTML, id: ids.next())

        case let directive as BlockDirective:
            let arguments = directive.argumentText.segments.map(\.untrimmedText).joined(separator: "\n")
            return .blockDirective(
                name: directive.name,
                arguments: arguments,
                blocks: parseBlocks(directive.children, ids: &ids),
                id: ids.next()
            )

        default:
            // Unknown / custom block — skip rather than guess its semantics.
            return nil
        }
    }

    private static func parseTable(_ table: Table, ids: inout SectionIDGenerator) -> MarklyBlock {
        let alignments = table.columnAlignments.map { $0.map(MarklyColumnAlignment.init(table:)) }
        func alignment(_ index: Int) -> MarklyColumnAlignment? {
            index < alignments.count ? alignments[index] : nil
        }
        let header: [MarklyTableCell] = table.head.cells.enumerated().map { index, cell in
            MarklyTableCell(inlines: InlineCollector.collect(cell.children), alignment: alignment(index))
        }
        let rows: [[MarklyTableCell]] = table.body.rows.map { row in
            row.cells.enumerated().map { index, cell in
                MarklyTableCell(inlines: InlineCollector.collect(cell.children), alignment: alignment(index))
            }
        }
        return .table(header: header, rows: rows, id: ids.next())
    }

    private static func headingHint(_ level: Int, _ inlines: [MarklyInline]) -> String {
        let slug = slugify(inlinePlainText(inlines))
        return slug.isEmpty ? "h\(level)" : "h\(level)-\(slug)"
    }
}

// MARK: - Inline collection

/// Walks swift-markdown inline nodes into `[MarklyInline]`.
fileprivate enum InlineCollector {
    static func collect(_ children: MarkupChildren) -> [MarklyInline] {
        var out: [MarklyInline] = []
        for child in children {
            switch child {
            case let text as Text:
                out.append(.text(text.string))
            case let code as InlineCode:
                out.append(.inlineCode(code.code))
            case let strong as Strong:
                out.append(.strong(collect(strong.children)))
            case let emphasis as Emphasis:
                out.append(.emphasis(collect(emphasis.children)))
            case let strike as Strikethrough:
                out.append(.strikethrough(collect(strike.children)))
            case let link as Link:
                out.append(.link(destination: link.destination ?? "", inlines: collect(link.children)))
            case let image as Image:
                out.append(.image(source: image.source ?? "", alt: altText(image.children)))
            case is SoftBreak:
                out.append(.softBreak)
            case is LineBreak:
                out.append(.lineBreak)
            default:
                // Unknown inline (e.g. custom inline): recurse into children, else skip.
                if child.childCount > 0 {
                    out.append(contentsOf: collect(child.children))
                }
            }
        }
        return out
    }

    /// Flattens inline `Markup` children to plain text (used for image alt text).
    static func altText(_ children: MarkupChildren) -> String {
        var text = ""
        for child in children {
            switch child {
            case let t as Text: text += t.string
            case let c as InlineCode: text += c.code
            case is SoftBreak, is LineBreak: text += " "
            default:
                if child.childCount > 0 { text += altText(child.children) }
            }
        }
        return text
    }
}

// MARK: - Plain-text helpers

/// Flattens `[MarklyInline]` to plain text (used for heading slugs and search indexing).
func inlinePlainText(_ inlines: [MarklyInline]) -> String {
    var text = ""
    for inline in inlines {
        switch inline {
        case .text(let t): text += t
        case .softBreak, .lineBreak: text += " "
        case .inlineCode(let c): text += c
        case .strong(let inner): text += inlinePlainText(inner)
        case .emphasis(let inner): text += inlinePlainText(inner)
        case .strikethrough(let inner): text += inlinePlainText(inner)
        case .link(_, let inner): text += inlinePlainText(inner)
        case .image(_, let alt): text += alt
        }
    }
    return text
}

/// Produces a URL-friendly slug from free text (GitHub-style: lowercase, letters/digits kept,
/// whitespace/punctuation collapsed to single hyphens).
func slugify(_ text: String) -> String {
    let lowered = text.lowercased()
    let mapped = lowered.map { character -> String in
        if character.isLetter || character.isNumber { return String(character) }
        return "-"
    }.joined()
    return mapped.split(separator: "-", omittingEmptySubsequences: true).joined(separator: "-")
}

// MARK: - Alignment bridging

fileprivate extension MarklyColumnAlignment {
    init(table alignment: Table.ColumnAlignment) {
        switch alignment {
        case .left: self = .left
        case .center: self = .center
        case .right: self = .right
        }
    }
}