//
//  MarklyListView.swift
//
//  Renders ordered and unordered lists (including nested lists) as a `VStack` of marker +
//  content rows. Unordered markers cycle by nesting depth (disc → circle → square, the
//  GitHub/MarkdownUI look); ordered markers use `.monospacedDigit()` so multi-digit numbers
//  align on the period. Each nesting depth indents the list by `listIndentStep`, and nested
//  list content reads an incremented `marklyListDepth` so the cycle continues. Markly owns list
//  layout: SwiftUI `Text` ignores block `PresentationIntent` from `AttributedString(markdown: .full)`
//  (see docs/Architecture.md §3).
//

import SwiftUI
import Cosmos

/// Renders a markdown list.
struct MarklyListView: View {
    /// `true` for ordered lists, `false` for bullet lists.
    let ordered: Bool
    /// The starting index for ordered lists (CommonMark default is 1).
    let start: Int?
    /// Each item is itself a list of nested blocks (a list item's content).
    let items: [[MarklyBlock]]

    @Environment(\.cosmosTheme) private var theme
    @Environment(\.marklyMarkdownTheme) private var md
    @Environment(\.marklyListDepth) private var depth

    /// Marker column min width, scaled with Dynamic Type so accessibility text sizes don't clip
    /// the marker gutter (Apple accessibility guidance: scale layout metrics that gate text).
    @ScaledMetric(relativeTo: .body) private var markerWidth: CGFloat = 28

    var body: some View {
        VStack(alignment: .leading, spacing: CosmosSpacingTokens.small) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, blocks in
                // When an item's first block leads with an image, the content side has no text
                // baseline to align to, so align the marker to the top of that first block; for
                // text-leading items, keep `.firstTextBaseline` so the marker sits on the first line.
                HStack(alignment: Self.firstBlockLeadsWithImage(blocks) ? .top : .firstTextBaseline,
                       spacing: CosmosSpacingTokens.small) {
                    markerView(for: index)
                        .foregroundStyle(theme.colors.primary)
                        .frame(minWidth: markerWidth, alignment: ordered ? .trailing : .leading)

                    MarklyBlockSequence(blocks: blocks, tight: true)
                        .environment(\.marklyListDepth, depth + 1)
                }
                // Read the marker and the item content as one VoiceOver element.
                .accessibilityElement(children: .combine)
            }
        }
        // Indent nested lists so depth is visible; the top-level list sits at the page padding.
        .padding(.leading, depth == 0 ? 0 : md.listIndentStep)
    }

    /// The marker for an item: a monospaced-digit ordinal for ordered lists, or the depth-cycled
    /// bullet for unordered lists.
    @ViewBuilder
    private func markerView(for index: Int) -> some View {
        if ordered {
            Text(verbatim: "\((start ?? 1) + index).")
                .marklyFont(size: CosmosTextStyle.body.pointSize)
                .monospacedDigit()
        } else {
            Text(verbatim: md.unorderedMarker(depth: depth))
                .marklyFont(size: CosmosTextStyle.body.pointSize)
        }
    }

    /// `true` if the item's first block is a paragraph that begins with an image (recursively
    /// through containers), in which case the row uses top alignment (no text baseline to share).
    private static func firstBlockLeadsWithImage(_ item: [MarklyBlock]) -> Bool {
        guard let firstBlock = item.first else { return false }
        if case .paragraph(let inlines, _) = firstBlock {
            return leadsWithImage(inlines)
        }
        return false
    }

    /// `true` if the inlines begin with an image, recursing through strong/emphasis/strikethrough/
    /// link so `**![alt](url)**` and `[![alt](url)](link)` are detected.
    private static func leadsWithImage(_ inlines: [MarklyInline]) -> Bool {
        guard let first = inlines.first else { return false }
        switch first {
        case .image:
            return true
        case .strong(let inner), .emphasis(let inner), .strikethrough(let inner):
            return leadsWithImage(inner)
        case .link(_, let inner):
            return leadsWithImage(inner)
        default:
            return false
        }
    }
}