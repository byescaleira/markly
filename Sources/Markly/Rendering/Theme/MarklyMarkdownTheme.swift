//
//  MarklyMarkdownTheme.swift
//  Markly
//
//  Markdown-specific typography + layout tokens for the GitHub-flavored reading layout,
//  layered on top of Cosmos color tokens. Colors stay Cosmos-driven (read from
//  `@Environment(\.cosmosTheme)`) so paper styles still adapt; this theme owns only the
//  markdown layout concerns Cosmos doesn't: per-level heading sizes/weights, the gap-before
//  spacing engine, list markers/indentation, code/table geometry. The default (`.github`) is
//  tuned to read like GitHub's markdown body, adapted to Apple's Dynamic Type via
//  ``MarklyScaledFont``. See docs/Architecture.md §3, §10.
//

import SwiftUI
import Cosmos

/// Markdown layout + typography tokens (color-free; colors come from Cosmos).
///
/// Kept `Sendable` so it can live in a SwiftUI `@Environment` value without Swift 6
/// concurrency warnings. All point values are *base* sizes; text-bearing sizes are scaled to
/// Dynamic Type at the call site via ``MarklyScaledFont`` (which reads the reader's
/// `.dynamicTypeSize` environment). Block gaps are fixed point values (layout metrics, not
/// text) — see §10.7 for the accessibility trade-off.
struct MarklyMarkdownTheme: Sendable {

    /// Per-level heading typography (index 0 = level 1).
    struct Heading: Sendable {
        /// Base point size (scaled with Dynamic Type via ``MarklyScaledFont``).
        let size: CGFloat
        /// Font weight — GitHub uses semibold (600) for every heading level.
        let weight: Font.Weight
        /// `true` for h1/h2, which carry a bottom hairline divider (the GitHub look).
        let showsDivider: Bool
    }

    /// Heading typography for levels 1–6 (index 0 = level 1).
    let headings: [Heading]

    // MARK: Gap-before spacing engine (applied as `.padding(.top, …)` in a zero-spacing stack)

    /// Gap before a heading. Larger than body gaps so headings breathe.
    let headingTopGap: CGFloat
    /// Gap before a paragraph.
    let paragraphTopGap: CGFloat
    /// Gap before a fenced code block.
    let codeTopGap: CGFloat
    /// Gap before a block quote.
    let blockQuoteTopGap: CGFloat
    /// Gap before a list.
    let listTopGap: CGFloat
    /// Gap before a table.
    let tableTopGap: CGFloat
    /// Gap before a thematic break (`---`).
    let thematicBreakTopGap: CGFloat
    /// Gap before a raw HTML block.
    let htmlTopGap: CGFloat
    /// Gap before a block directive.
    let blockDirectiveTopGap: CGFloat
    /// Gap used inside tight containers (list items, block quotes) — smaller than the page gap.
    let tightTopGap: CGFloat

    // MARK: Block geometry

    /// Extra line spacing between wrapped lines of a paragraph.
    let paragraphLineSpacing: CGFloat
    /// Corner radius of the code-block card.
    let codeCornerRadius: CGFloat
    /// Inner padding of the code-block card.
    let codePadding: CGFloat
    /// Width of the block-quote leading bar.
    let blockQuoteBarWidth: CGFloat
    /// Corner radius of the block-quote card (accent-tinted background).
    let blockQuoteCornerRadius: CGFloat
    /// Width of table grid lines (also the Grid cell spacing).
    let tableBorderWidth: CGFloat
    /// Horizontal padding inside a table cell (GitHub: 13).
    let tableCellPaddingH: CGFloat
    /// Vertical padding inside a table cell (GitHub: 6).
    let tableCellPaddingV: CGFloat

    // MARK: Lists

    /// Leading indent added per nesting depth.
    let listIndentStep: CGFloat
    /// Unordered list markers cycled by depth: disc, circle, square.
    let listMarkers: [String]

    /// The GitHub-flavored default, adapted to Apple's type scale (body = 17pt).
    static let github = MarklyMarkdownTheme(
        headings: [
            .init(size: 32, weight: .semibold, showsDivider: true),   // h1
            .init(size: 24, weight: .semibold, showsDivider: true),   // h2
            .init(size: 21, weight: .semibold, showsDivider: false),   // h3
            .init(size: 17, weight: .semibold, showsDivider: false),   // h4
            .init(size: 15, weight: .semibold, showsDivider: false),   // h5
            .init(size: 14, weight: .semibold, showsDivider: false)    // h6
        ],
        headingTopGap: 24,
        paragraphTopGap: 16,
        codeTopGap: 16,
        blockQuoteTopGap: 16,
        listTopGap: 16,
        tableTopGap: 16,
        thematicBreakTopGap: 24,
        htmlTopGap: 16,
        blockDirectiveTopGap: 16,
        tightTopGap: 8,
        paragraphLineSpacing: 4,
        codeCornerRadius: 16,
        codePadding: 16,
        blockQuoteBarWidth: 3,
        blockQuoteCornerRadius: 8,
        tableBorderWidth: 1,
        tableCellPaddingH: 13,
        tableCellPaddingV: 6,
        listIndentStep: 24,
        listMarkers: ["•", "◦", "▪"]
    )

    /// Heading typography for a 1-based level, clamped to 1–6.
    func heading(for level: Int) -> Heading {
        let clamped = min(max(level, 1), 6)
        return headings[clamped - 1]
    }

    /// The unordered-list marker for a (0-based) nesting depth, cycling disc → circle → square.
    func unorderedMarker(depth: Int) -> String {
        guard !listMarkers.isEmpty else { return "•" }
        return listMarkers[depth % listMarkers.count]
    }

    /// The gap-before value for a block in a sequence. `tight` containers (list items, block
    /// quotes) use a single smaller gap regardless of block kind, matching GitHub's compact
    /// nested spacing.
    func topGap(for block: MarklyBlock, tight: Bool) -> CGFloat {
        if tight { return tightTopGap }
        switch block {
        case .heading: return headingTopGap
        case .paragraph: return paragraphTopGap
        case .codeBlock: return codeTopGap
        case .blockQuote: return blockQuoteTopGap
        case .list: return listTopGap
        case .table: return tableTopGap
        case .thematicBreak: return thematicBreakTopGap
        case .htmlBlock: return htmlTopGap
        case .blockDirective: return blockDirectiveTopGap
        }
    }
}

// MARK: - Environment

private struct MarklyMarkdownThemeKey: EnvironmentKey {
    static let defaultValue: MarklyMarkdownTheme = .github
}

extension EnvironmentValues {
    /// The markdown layout/typography theme. Defaults to ``MarklyMarkdownTheme/github``.
    var marklyMarkdownTheme: MarklyMarkdownTheme {
        get { self[MarklyMarkdownThemeKey.self] }
        set { self[MarklyMarkdownThemeKey.self] = newValue }
    }
}

// MARK: - Scaled font

/// Applies a Dynamic-Type-scaled `Font.system(size:weight:)`. `Font.system(size:)` with a fixed
/// size does not itself opt into Dynamic Type, so the size is resolved through `@ScaledMetric`
/// (which reads the reader's `.dynamicTypeSize` environment) — this is how the aA font-size slider
/// scales headings, list markers, code, and table text. Mirrors MarkdownUI's
/// `ScaledFontSizeModifier` (see docs/Architecture.md §3).
private struct MarklyScaledFont: ViewModifier {
    let baseSize: CGFloat
    let weight: Font.Weight
    @ScaledMetric private var size: CGFloat

    init(baseSize: CGFloat, weight: Font.Weight) {
        self.baseSize = baseSize
        self.weight = weight
        _size = ScaledMetric(wrappedValue: baseSize, relativeTo: .body)
    }

    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: weight))
    }
}

extension View {
    /// A Dynamic-Type-scaled system font at a fixed base size and weight.
    func marklyFont(size: CGFloat, weight: Font.Weight = .regular) -> some View {
        modifier(MarklyScaledFont(baseSize: size, weight: weight))
    }
}