//
//  MarklySearch.swift
//  Markly
//
//  Pure, Sendable, Codable in-document search over the parsed `[MarklyBlock]` model — the
//  same pattern `MarklyTOC` uses. Walks blocks in document order, flattens each block to plain
//  text (recursing into block quotes, list items, block directives, and table cells), finds
//  every occurrence of the query, and emits one `MarklySearchResult` per occurrence scoped to
//  the enclosing heading section (the nearest preceding heading, or the matched block itself
//  for front matter before the first heading).
//
//  Independent of Nebula and SwiftUI — unit-testable on its own. The reading surface scrolls
//  to a result's `sectionID` via `ScrollViewReader` (see MarklyReaderView / MarklyReaderController).
//

import Foundation

/// Options for in-document search.
public struct MarklySearchOptions: Sendable, Equatable, Codable {
    /// `true` to match case exactly; `false` (default) to match case-insensitively.
    public var caseSensitive: Bool
    /// `true` to match only whole words (alphanumeric boundaries); `false` (default) to match
    /// substrings anywhere.
    public var wholeWord: Bool

    /// Creates search options.
    public init(caseSensitive: Bool = false, wholeWord: Bool = false) {
        self.caseSensitive = caseSensitive
        self.wholeWord = wholeWord
    }

    /// The defaults: case-insensitive substring matching.
    public static let `default` = MarklySearchOptions()
}

/// A single search hit: where it is, what section it belongs to, and a windowed snippet with
/// the match highlighted.
public struct MarklySearchResult: Sendable, Equatable, Hashable, Codable, Identifiable {
    /// The block containing the match (used for stable identity across query keystrokes).
    public let blockID: MarklySectionID
    /// The scroll target: the enclosing heading's id, or `blockID` for front matter before the
    /// first heading. Tapping a result scrolls here.
    public let sectionID: MarklySectionID
    /// The enclosing heading's plain-text title, or `"Start of document"` for front matter.
    public let sectionTitle: String
    /// A windowed snippet of the block's plain text around the match (with `…` ellipses when
    /// truncated). The match sits at `matchRange` within this string.
    public let snippet: String
    /// The range of the match within `snippet` (character indices), for highlight rendering.
    public let matchRange: Range<Int>
    /// The character offset of the match start within the block's full plain text (used for a
    /// stable, unique identity).
    public let matchOffset: Int

    /// A stable, unique identity: the block plus the absolute match offset.
    public var id: String { "\(blockID.raw)#\(matchOffset)" }

    /// Creates a search result.
    public init(
        blockID: MarklySectionID,
        sectionID: MarklySectionID,
        sectionTitle: String,
        snippet: String,
        matchRange: Range<Int>,
        matchOffset: Int
    ) {
        self.blockID = blockID
        self.sectionID = sectionID
        self.sectionTitle = sectionTitle
        self.snippet = snippet
        self.matchRange = matchRange
        self.matchOffset = matchOffset
    }
}

/// Derives in-document search results from parsed blocks.
public enum MarklySearch {

    /// The plain-text title shown for a match that precedes the document's first heading.
    public static let startOfDocumentTitle = "Start of document"

    /// Returns every match of `query` in `blocks`, scoped to the enclosing heading section.
    /// An empty or whitespace-only `query` yields no results.
    public static func results(
        for query: String,
        in blocks: [MarklyBlock],
        options: MarklySearchOptions = .default
    ) -> [MarklySearchResult] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return [] }

        var out: [MarklySearchResult] = []
        var currentHeading: (id: MarklySectionID, title: String)?

        for block in blocks {
            if case .heading(_, let inlines, let id) = block {
                currentHeading = (id, inlinePlainText(inlines))
            }
            let text = blockPlainText(block)
            for match in allMatches(needle, in: text, options) {
                let sectionID = currentHeading?.id ?? block.id
                let sectionTitle = currentHeading?.title ?? Self.startOfDocumentTitle
                let matchOffset = text.distance(from: text.startIndex, to: match.lowerBound)
                let window = Self.snippet(around: match, in: text)
                out.append(MarklySearchResult(
                    blockID: block.id,
                    sectionID: sectionID,
                    sectionTitle: sectionTitle,
                    snippet: window.snippet,
                    matchRange: window.matchRange,
                    matchOffset: matchOffset
                ))
            }
        }
        return out
    }

    // MARK: - Block plain text

    /// Flattens a block (recursing into nested blocks) to a single plain-text string, joining
    /// nested block text with spaces. Headings/paragraphs use inline plain text; code blocks
    /// and HTML blocks use their raw content; tables flatten header + body cells.
    static func blockPlainText(_ block: MarklyBlock) -> String {
        switch block {
        case .heading(_, let inlines, _):
            return inlinePlainText(inlines)
        case .paragraph(let inlines, _):
            return inlinePlainText(inlines)
        case .codeBlock(_, let code, _):
            return code
        case .blockQuote(let blocks, _):
            return blocks.map { blockPlainText($0) }.joined(separator: " ")
        case .list(_, _, let items, _):
            return items.flatMap { $0.map { blockPlainText($0) } }.joined(separator: " ")
        case .thematicBreak:
            return ""
        case .table(let header, let rows, _):
            let cells = header + rows.flatMap { $0 }
            return cells.map { inlinePlainText($0.inlines) }.joined(separator: " ")
        case .htmlBlock(let html, _):
            return html
        case .blockDirective(_, _, let blocks, _):
            return blocks.map { blockPlainText($0) }.joined(separator: " ")
        }
    }

    // MARK: - Matching

    /// Returns every (non-overlapping) match of `needle` in `haystack` honoring the options.
    static func allMatches(
        _ needle: String,
        in haystack: String,
        _ options: MarklySearchOptions
    ) -> [Range<String.Index>] {
        guard !needle.isEmpty else { return [] }
        var compareOptions: String.CompareOptions = []
        if !options.caseSensitive { compareOptions.insert(.caseInsensitive) }

        var matches: [Range<String.Index>] = []
        var searchRange = haystack.startIndex..<haystack.endIndex
        while let r = haystack.range(of: needle, options: compareOptions, range: searchRange) {
            if options.wholeWord, !isWholeWord(haystack, r) {
                if r.upperBound < haystack.endIndex {
                    searchRange = r.upperBound..<haystack.endIndex
                } else {
                    break
                }
                continue
            }
            matches.append(r)
            if r.upperBound < haystack.endIndex {
                searchRange = r.upperBound..<haystack.endIndex
            } else {
                break
            }
        }
        return matches
    }

    /// `true` when the match is bounded by non-word characters (or the string ends), so it is a
    /// whole word rather than a substring of a larger word.
    private static func isWholeWord(_ s: String, _ r: Range<String.Index>) -> Bool {
        let isWordChar: (Character) -> Bool = { $0.isLetter || $0.isNumber }
        let leftOK = r.lowerBound == s.startIndex || !isWordChar(s[s.index(before: r.lowerBound)])
        let rightOK = r.upperBound == s.endIndex || !isWordChar(s[r.upperBound])
        return leftOK && rightOK
    }

    /// A windowed snippet around `match` in `text`, with `…` ellipses when truncated, and the
    /// match's range re-mapped into the snippet's character indices.
    static func snippet(
        around match: Range<String.Index>,
        in text: String,
        window: Int = 60
    ) -> (snippet: String, matchRange: Range<Int>) {
        let startDist = text.distance(from: text.startIndex, to: match.lowerBound)
        let endDist = text.distance(from: text.startIndex, to: match.upperBound)

        let lowerIdx = text.index(text.startIndex, offsetBy: max(0, startDist - window))
        let upperIdx = text.index(
            text.startIndex,
            offsetBy: min(text.count, endDist + window)
        )

        var middle = String(text[lowerIdx..<upperIdx])
        let matchStartInMiddle = text.distance(from: lowerIdx, to: match.lowerBound)
        let matchEndInMiddle = text.distance(from: lowerIdx, to: match.upperBound)

        var prefix = ""
        if lowerIdx != text.startIndex { prefix = "…" }
        if upperIdx != text.endIndex { middle += "…" }

        let snippet = prefix + middle
        let offset = prefix.count
        let matchRange = (matchStartInMiddle + offset)..<(matchEndInMiddle + offset)
        return (snippet, matchRange)
    }
}