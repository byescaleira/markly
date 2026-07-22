//
//  MarklyTOCView.swift
//  Markly
//
//  The table-of-contents surface: a scrollable list of headings, indented by level, with the
//  current section highlighted. Selecting an entry calls `onSelect(id)`, which the reader routes
//  to `ScrollViewReader.scrollTo` to jump to that heading. Styled from Cosmos theme tokens.
//

import SwiftUI
import Cosmos

/// A table-of-contents list.
struct MarklyTOCView: View {
    /// The TOC entries (headings in document order).
    let entries: [MarklyTOCEntry]
    /// The section currently in view (highlighted), if any.
    let currentID: MarklySectionID?
    /// Called with a section id when the user selects an entry.
    let onSelect: (MarklySectionID) -> Void

    @Environment(\.cosmosTheme) private var theme

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: CosmosSpacingTokens.small) {
                ForEach(entries) { entry in
                    Button {
                        onSelect(entry.id)
                    } label: {
                        HStack(alignment: .top, spacing: CosmosSpacingTokens.small) {
                            // Indent by level (cap at 5 so deep headings don't run off-screen).
                            Spacer().frame(width: indentation(for: entry.level))
                            Text(verbatim: entry.title)
                                .font(theme.typography.font(for: titleStyle(entry.level)))
                                .foregroundStyle(entry.id == currentID ? theme.colors.accent : theme.colors.primary)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    // Mirror the accent-color "current section" cue for VoiceOver: the selected row
                    // gains the `.isSelected` trait + an explicit value, so a blind user can tell
                    // which heading they're currently on (the color alone conveys nothing aurally).
                    .accessibilityAddTraits(entry.id == currentID ? .isSelected : [])
                    .accessibilityValue(entry.id == currentID ? Text("Current section", bundle: .module) : Text(""))
                }
            }
            .padding(CosmosSpacingTokens.medium)
        }
        .background(theme.colors.background)
    }

    /// Per-level indentation, scaled modestly so the hierarchy reads without consuming the row.
    private func indentation(for level: Int) -> CGFloat {
        CGFloat(max(0, min(level, 6) - 1)) * CosmosSpacingTokens.medium
    }

    /// Heading level → Cosmos text style (slightly smaller than the rendered heading so the TOC
    /// stays compact).
    private func titleStyle(_ level: Int) -> CosmosTextStyle {
        switch level {
        case 1: .title3
        case 2: .headline
        case 3: .body
        default: .subheadline
        }
    }
}