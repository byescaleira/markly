//
//  MarklyTableView.swift
//
//  Renders a markdown table as a SwiftUI `Grid` with per-column alignment, alternating row
//  backgrounds, a semibold header, and hairline borders. Borders are drawn with the
//  gutter-fill technique: the Grid's own background is the border color, cell spacing equals the
//  border width, and each cell carries an opaque row background that masks the border everywhere
//  except the gutters — so the gutters read as grid lines without any anchor-preference
//  measurement (robust inside a `LazyVStack`). Wrapped in a horizontal `ScrollView` so wide tables
//  scroll instead of clipping; cells use `.fixedSize(horizontal: true, vertical: false)` so each
//  column takes its intrinsic content width. Cosmos has no table atom, so Markly owns table
//  layout (see docs/Architecture.md §3, §10).
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
    @Environment(\.marklyMarkdownTheme) private var md

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .topLeading, horizontalSpacing: md.tableBorderWidth, verticalSpacing: md.tableBorderWidth) {
                GridRow {
                    ForEach(Array(header.enumerated()), id: \.offset) { _, cell in
                        cellView(cell, isHeader: true, row: -1)
                            .accessibilityAddTraits(.isHeader)
                    }
                }
                ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                            cellView(cell, isHeader: false, row: rowIndex)
                        }
                    }
                }
            }
            // Room for the outer border, then fill behind the Grid with the border color so the
            // cell gutters (sized to `tableBorderWidth`) read as grid lines.
            .padding(md.tableBorderWidth)
            .background(theme.colors.outline)
        }
    }

    private func cellView(_ cell: MarklyTableCell, isHeader: Bool, row: Int) -> some View {
        MarklyInlineText(
            inlines: cell.inlines,
            baseSize: CosmosTextStyle.body.pointSize,
            weight: isHeader ? .semibold : .regular
        )
        .foregroundStyle(theme.colors.primary)
        .multilineTextAlignment(textAlignment(cell.alignment))
        .fixedSize(horizontal: true, vertical: false)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: frameAlignment(cell.alignment))
        .padding(.horizontal, md.tableCellPaddingH)
        .padding(.vertical, md.tableCellPaddingV)
        .background(rowBackground(isHeader: isHeader, row: row))
    }

    /// GitHub-style alternating rows: header on the elevated surface; body rows alternate between
    /// the page background and the elevated surface.
    private func rowBackground(isHeader: Bool, row: Int) -> Color {
        if isHeader { return theme.colors.surface }
        return row.isMultiple(of: 2) ? theme.colors.surface : theme.colors.background
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