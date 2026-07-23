//
//  MarklyBlockView.swift
//
//  The per-block SwiftUI renderer. Switches on `MarklyBlock` and produces a view per case,
//  styling from `@Environment(\.cosmosTheme)` (Cosmos color tokens) and
//  `@Environment(\.marklyMarkdownTheme)` (markdown typography + layout), and applying
//  accessibility traits. Inline markdown routes through `MarklyInlineText` (native
//  `Text(AttributedString)`); block spacing is owned by `MarklyBlockSequence` (see
//  docs/Architecture.md §3, §10).
//

import SwiftUI
import Cosmos

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
        case .heading(let level, let inlines, let id):
            let heading = md.heading(for: level)
            VStack(alignment: .leading, spacing: CosmosSpacingTokens.small) {
                MarklyInlineText(inlines: inlines, baseSize: heading.size, weight: heading.weight)
                    .foregroundStyle(level >= 6 ? theme.colors.secondary : theme.colors.primary)
                    .accessibilityHeading(Self.accessibilityHeadingLevel(level))
                if heading.showsDivider {
                    Divider()
                        .background(theme.colors.outline)
                }
            }
            .id(id)
            .onAppear { sectionObserver(id) }

        case .paragraph(let inlines, let id):
            paragraphBody(inlines: inlines, id: id)

        case .codeBlock(let language, let code, let id):
            MarklyCodeBlockView(language: language, code: code)
                .id(id)

        case .blockQuote(let blocks, let id):
            HStack(alignment: .top, spacing: CosmosSpacingTokens.small) {
                Rectangle()
                    .fill(theme.colors.outline)
                    .frame(width: md.blockQuoteBarWidth)
                MarklyBlockSequence(blocks: blocks, tight: true)
            }
            .id(id)

        case .list(let ordered, let start, let items, let id):
            MarklyListView(ordered: ordered, start: start, items: items)
                .id(id)

        case .thematicBreak(let id):
            CosmosDivider()
                .id(id)

        case .table(let header, let rows, let id):
            MarklyTableView(header: header, rows: rows)
                .id(id)

        case .htmlBlock(let html, let id):
            // Apple-only: render raw HTML as verbatim preformatted text (no inline HTML rendering).
            CosmosText(verbatim: html)
                .cosmosTextStyle(.footnote)
                .id(id)

        case .blockDirective(_, _, let blocks, let id):
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