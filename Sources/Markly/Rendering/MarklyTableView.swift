//
//  MarklyTableView.swift
//  Markly
//
//  Renders a markdown table as a SwiftUI `Grid` with per-column alignment. Wrapped in a
//  horizontal `ScrollView` so wide tables scroll instead of clipping: cells use
//  `.fixedSize(horizontal: true, vertical: false)` so each column takes its intrinsic content
//  width (rather than `.frame(maxWidth: .infinity)`, which flexes columns to share the visible
//  width and dead-locks the scroll). Cosmos has no table atom, so Markly owns table layout
//  (see docs/Architecture.md §3, §10).
//

import SwiftUI
import Cosmos

/// Renders a markdown table.
struct MarklyTableView: View {
    /// The header row cells.
    let header: [MarklyTableCell]
    /// The body rows, each a list of cells.
    let rows: [[MarklyTableCell]]

    @Environment(\.cosmosTheme) private var theme

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .topLeading, horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    ForEach(Array(header.enumerated()), id: \.offset) { _, cell in
                        cellView(cell, isHeader: true)
                            .accessibilityAddTraits(.isHeader)
                    }
                }
                .background(theme.colors.surface)

                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                            cellView(cell, isHeader: false)
                        }
                    }
                    .overlay(Divider())
                }
            }
        }
    }

    private func cellView(_ cell: MarklyTableCell, isHeader: Bool) -> some View {
        MarklyInlineText(inlines: cell.inlines)
            .font(theme.typography.font(for: isHeader ? .headline : .body))
            .foregroundStyle(theme.colors.primary)
            .multilineTextAlignment(textAlignment(cell.alignment))
            .fixedSize(horizontal: true, vertical: false)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: frameAlignment(cell.alignment))
            .padding(CosmosSpacingTokens.small)
    }

    private func textAlignment(_ alignment: MarklyColumnAlignment?) -> TextAlignment {
        switch alignment {
        case .right: .trailing
        case .center: .center
        case .left, nil: .leading
        }
    }

    private func frameAlignment(_ alignment: MarklyColumnAlignment?) -> Alignment {
        switch alignment {
        case .right: .trailing
        case .center: .center
        case .left, nil: .leading
        }
    }
}