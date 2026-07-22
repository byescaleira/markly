//
//  MarklyListView.swift
//  Markly
//
//  Renders ordered and unordered lists (including nested lists) as a SwiftUI `VStack` of
//  marker + content rows. Markly owns list layout: SwiftUI `Text` ignores block
//  `PresentationIntent` from `AttributedString(markdown: .full)` (see docs/Architecture.md §3).
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

    /// Marker column min width, scaled with Dynamic Type so accessibility text sizes don't clip
    /// the marker gutter (Apple accessibility guidance: scale layout metrics that gate text).
    @ScaledMetric private var markerWidth: CGFloat = 18

    var body: some View {
        VStack(alignment: .leading, spacing: CosmosSpacingTokens.small) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, blocks in
                HStack(alignment: .top, spacing: CosmosSpacingTokens.small) {
                    Text(verbatim: marker(for: index))
                        .font(theme.typography.font(for: .body))
                        .foregroundStyle(theme.colors.primary)
                        .frame(minWidth: markerWidth, alignment: .leading)

                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(blocks, id: \.id) { block in
                            MarklyBlockView(block: block)
                        }
                    }
                }
                // Read the marker and the item content as one VoiceOver element.
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func marker(for index: Int) -> String {
        ordered ? "\((start ?? 1) + index)." : "•"
    }
}