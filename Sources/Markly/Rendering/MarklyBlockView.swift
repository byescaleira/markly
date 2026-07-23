//
//  MarklyBlockView.swift
//
//  The per-block SwiftUI renderer. It splits Markly's `MarklyBlock` AST into two paths:
//
//  • Leaf blocks with no nested *selectable* paragraphs — heading, codeBlock, thematicBreak,
//    htmlBlock — are converted to a MarkdownUI `BlockNode` (via `MarklyBlockNodeConverter`) and
//    rendered through the vendored MarkdownUI block views + Theme system. This is where Markly
//    uses gonzalezreal/swift-markdown-ui's rendering code (headings, code blocks, rules, HTML).
//
//  • Paragraphs, block quotes, lists, tables, and block directives stay on Markly's own renderer.
//    Paragraphs are the highlight surface: their selectable text ranges are a byte-for-byte round
//    trip through `MarklyInlineSerializer` + Foundation, and routing them through MarkdownUI's
//    direct `InlineNode → AttributedString` renderer would misalign saved highlights. Block
//    quotes, lists, and block directives stay on Markly's recursive container so paragraphs keep
//    selectability at every nesting level. Tables stay on `MarklyTableView` (horizontal scroll
//    for wide tables + Cosmos styling). See docs/Architecture.md §3, §10.
//
//  Block spacing is owned by `MarklyBlockSequence` (the gap-before engine); MarkdownUI's own
//  `BlockSequence` margins are no-ops for a standalone `BlockNode`, so there is no double spacing.
//

import SwiftUI
import Cosmos
import MarkdownUI

/// Renders a single markdown block.
struct MarklyBlockView: View {
    /// The block to render.
    let block: MarklyBlock

    @Environment(\.cosmosTheme) private var theme
    @Environment(\.marklyMarkdownTheme) private var md
    @Environment(\.marklySectionObserver) private var sectionObserver
    @Environment(\.marklyReaderFeatures) private var features
    @Environment(\.marklyReaderFontSize) private var fontSize
    @Environment(\.marklyHighlightsProvider) private var highlightsProvider
    @Environment(\.marklySelectionObserver) private var selectionObserver

    var body: some View {
        switch block {
        case .heading(let level, _, let id):
            // Routed through MarkdownUI's `HeadingView` + the GitHub heading styles (Cosmos
            // divider for h1/h2). The section observer registers the heading for TOC / scroll
            // anchors; VoiceOver gets the heading level.
            MarklyBlockNodeConverter.block(block)
                .id(id)
                .onAppear { sectionObserver(id) }
                .accessibilityHeading(Self.accessibilityHeadingLevel(level))

        case .paragraph(let inlines, let id):
            paragraphBody(inlines: inlines, id: id)

        case .codeBlock(_, _, let id):
            // Routed through MarkdownUI's `CodeBlockView`; the code-block style is overridden at
            // the reader with `MarklyCodeBlockCard` (Copy button + Cosmos card), so Markly keeps
            // its e-reader chrome while using MarkdownUI's code-block + syntax-highlighter plumbing.
            MarklyBlockNodeConverter.block(block)
                .id(id)

        case .blockQuote(let blocks, let id):
            // Stays on Markly's recursive container so nested paragraphs keep their selectable
            // highlights. MarkdownUI's `BlockquoteView` would render nested paragraphs as
            // non-selectable `Text`, regressing the highlight feature inside quotes.
            HStack(alignment: .top, spacing: CosmosSpacingTokens.small) {
                Rectangle()
                    .fill(theme.colors.outline)
                    .frame(width: md.blockQuoteBarWidth)
                MarklyBlockSequence(blocks: blocks, tight: true)
                    .padding(.trailing, CosmosSpacingTokens.small)
            }
            .padding(.vertical, CosmosSpacingTokens.small)
            // Accent-tinted card (10% accent) with rounded corners. `clipShape` rounds the
            // leading bar's corners to the card's radius so the bar integrates with the rounded
            // background instead of its square corners poking out of it.
            .background(
                RoundedRectangle(cornerRadius: md.blockQuoteCornerRadius, style: .continuous)
                    .fill(theme.colors.accent.opacity(0.1))
            )
            .clipShape(RoundedRectangle(cornerRadius: md.blockQuoteCornerRadius, style: .continuous))
            // `.fixedSize(horizontal: false, vertical: true)` pins the bar to the quote content's
            // natural height. The `Rectangle` has a width-only frame, so without this it is
            // height-flexible and stretches to whatever height the parent container proposes,
            // making the accent bar visibly taller than the quoted text. Horizontal stays flexible
            // so the text still wraps to the available width. Mirrors the vendored GitHub
            // blockquote style in `Theme+Markly.swift`.
            .fixedSize(horizontal: false, vertical: true)
            .id(id)

        case .list(let ordered, let start, let items, let id):
            // Stays on Markly's recursive list view so nested list-item paragraphs keep selectable
            // highlights and markers cycle by nesting depth.
            MarklyListView(ordered: ordered, start: start, items: items)
                .id(id)

        case .thematicBreak(let id):
            // Routed through MarkdownUI's `ThematicBreakView` (Cosmos-colored rule).
            MarklyBlockNodeConverter.block(block)
                .id(id)

        case .table(let header, let rows, let id):
            // Stays on `MarklyTableView`: horizontal scroll for wide tables + Cosmos styling,
            // which MarkdownUI's `TableView` does not provide out of the box.
            MarklyTableView(header: header, rows: rows)
                .id(id)

        case .htmlBlock(_, let id):
            // Routed through MarkdownUI's `ParagraphView(content:)` — raw HTML renders as
            // verbatim text (no inline-HTML rendering; Apple-only stack). The html string isn't
            // bound: `MarklyBlockNodeConverter.block(block)` consumes the whole enum value.
            MarklyBlockNodeConverter.block(block)
                .id(id)

        case .blockDirective(_, _, let blocks, let id):
            // Stays on Markly's recursive container (no MarkdownUI equivalent for block directives).
            MarklyBlockSequence(blocks: blocks, tight: true)
                .id(id)
        }
    }

    /// Renders a paragraph. On iOS/iPadOS/visionOS/macOS, when highlights are enabled and the
    /// paragraph holds no inline image, routes through `MarklySelectableText` (a real text view
    /// that captures the selection range and draws existing highlight backgrounds/underlines).
    /// Otherwise — and always on tvOS, which has no text selection — falls back to the native
    /// `Text` path via `MarklyInlineText`.
    @ViewBuilder
    private func paragraphBody(inlines: [MarklyInline], id: MarklySectionID) -> some View {
        #if !os(tvOS)
        if features.highlights && !MarklyInlineText.containsImage(inlines) {
            MarklySelectableText(
                inlines: inlines,
                basePointSize: CosmosTextStyle.body.pointSize,
                textColor: theme.colors.primary,
                fontSize: fontSize,
                highlights: highlightsProvider(id),
                onSelection: { range in selectionObserver(id, range) }
            )
            .id(id)
        } else {
            textParagraph(inlines: inlines, id: id)
        }
        #else
        textParagraph(inlines: inlines, id: id)
        #endif
    }

    /// The non-selectable `Text` paragraph (used when highlights are off, the paragraph contains
    /// an inline image, or the platform is tvOS).
    @ViewBuilder
    private func textParagraph(inlines: [MarklyInline], id: MarklySectionID) -> some View {
        MarklyInlineText(inlines: inlines)
            .foregroundStyle(theme.colors.primary)
            .lineSpacing(md.paragraphLineSpacing)
            .id(id)
    }

    /// Maps a heading level to a SwiftUI accessibility heading level for VoiceOver.
    private static func accessibilityHeadingLevel(_ level: Int) -> AccessibilityHeadingLevel {
        switch level {
        case 1: .h1
        case 2: .h2
        case 3: .h3
        case 4: .h4
        case 5: .h5
        default: .h6
        }
    }
}