//
//  MarklyHighlightsView.swift
//  Markly
//
//  The highlights list: each row shows the highlighted excerpt with its color swatch (and a note
//  indicator). Tap to jump to the highlight's section; long-press / right-click for a Delete
//  action. Styled from Cosmos theme tokens. Shown in the reader sheet's Highlights tab.
//

import SwiftUI
import Cosmos

/// A highlights list.
struct MarklyHighlightsView: View {
    /// The current book's highlights.
    let highlights: [MarklyHighlight]
    /// Returns the plain-text excerpt for a highlight (over its range in its section).
    let excerpt: (MarklyHighlight) -> String
    /// Jump to a highlight's section.
    let onSelect: (MarklySectionID) -> Void
    /// Delete a highlight by id.
    let onDelete: (UUID) -> Void

    @Environment(\.cosmosTheme) private var theme

    var body: some View {
        ScrollView {
            if highlights.isEmpty {
                VStack(spacing: CosmosSpacingTokens.small) {
                    Image(systemName: "highlighter")
                        .font(.system(size: 28))
                        .foregroundStyle(theme.colors.secondary)
                    Text("No highlights yet.", bundle: .module)
                        .foregroundStyle(theme.colors.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                LazyVStack(alignment: .leading, spacing: CosmosSpacingTokens.small) {
                    ForEach(highlights) { highlight in
                        Button {
                            onSelect(highlight.sectionID)
                        } label: {
                            HStack(alignment: .top, spacing: CosmosSpacingTokens.small) {
                                // Color swatch (a rounded rect for marker colors, an underline glyph for underline).
                                swatch(for: highlight.color)
                                VStack(alignment: .leading, spacing: CosmosSpacingTokens.xs) {
                                    Text(verbatim: excerpt(highlight))
                                        .font(theme.typography.font(for: .body))
                                        .foregroundStyle(theme.colors.primary)
                                        .lineLimit(3)
                                    if let note = highlight.note, !note.isEmpty {
                                        HStack(spacing: CosmosSpacingTokens.xs) {
                                            Image(systemName: "note.text")
                                                .font(.system(size: 12))
                                                .foregroundStyle(theme.colors.secondary)
                                            Text(verbatim: note)
                                                .font(theme.typography.font(for: .caption))
                                                .foregroundStyle(theme.colors.secondary)
                                                .lineLimit(2)
                                        }
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(CosmosSpacingTokens.small)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        // Announce the color before the excerpt (and the note), so VoiceOver conveys
                        // the same cue the swatch gives visually. The swatch itself is decorative.
                        .accessibilityLabel(rowLabel(for: highlight))
                        .contextMenu {
                            Button(role: .destructive) {
                                onDelete(highlight.id)
                            } label: {
                                Label { Text("Delete", bundle: .module) } icon: {
                                    Image(systemName: "trash")
                                }
                            }
                        }
                    }
                }
                .padding(CosmosSpacingTokens.medium)
            }
        }
        .background(theme.colors.background)
    }

    @ViewBuilder
    private func swatch(for color: MarklyHighlightColor) -> some View {
        if color.isUnderline {
            Image(systemName: "underline")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.colors.primary)
                .frame(width: 20, height: 20)
                .accessibilityHidden(true)
        } else {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(color.color)
                .frame(width: 20, height: 20)
                .accessibilityHidden(true)
        }
    }

    /// The spoken row label: the color name, then the excerpt, then any note. The localized parts
    /// (the color name, "Note") interpolate as `Text` so they localize; the dynamic excerpt/note
    /// interpolate as `String` so they're treated as verbatim (non-localized) runtime values.
    private func rowLabel(for highlight: MarklyHighlight) -> Text {
        if let note = highlight.note, !note.isEmpty {
            return Text("\(Text(highlight.color.accessibilityName, bundle: .module)), \(excerpt(highlight)), \(Text("Note", bundle: .module)): \(note)")
        }
        return Text("\(Text(highlight.color.accessibilityName, bundle: .module)), \(excerpt(highlight))")
    }
}