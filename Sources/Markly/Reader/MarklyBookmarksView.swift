//
//  MarklyBookmarksView.swift
//  Markly
//
//  The bookmarks list: tap a bookmark to jump to its section; long-press / right-click for a
//  Delete action. Styled from Cosmos theme tokens. Shown in the reader sheet's Bookmarks tab.
//

import SwiftUI
import Cosmos

/// A bookmarks list.
struct MarklyBookmarksView: View {
    /// The current book's bookmarks.
    let bookmarks: [MarklyBookmark]
    /// Jump to a bookmark's section.
    let onSelect: (MarklySectionID) -> Void
    /// Delete a bookmark by id.
    let onDelete: (UUID) -> Void

    @Environment(\.cosmosTheme) private var theme

    var body: some View {
        ScrollView {
            if bookmarks.isEmpty {
                VStack(spacing: CosmosSpacingTokens.small) {
                    Image(systemName: "bookmark")
                        .font(.system(size: 28))
                        .foregroundStyle(theme.colors.secondary)
                    Text("No bookmarks yet.", bundle: .module)
                        .foregroundStyle(theme.colors.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                LazyVStack(alignment: .leading, spacing: CosmosSpacingTokens.small) {
                    ForEach(bookmarks) { bookmark in
                        Button {
                            onSelect(bookmark.sectionID)
                        } label: {
                            HStack(spacing: CosmosSpacingTokens.small) {
                                Image(systemName: "bookmark.fill")
                                    .foregroundStyle(theme.colors.accent)
                                Text(verbatim: bookmark.title)
                                    .foregroundStyle(theme.colors.primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(CosmosSpacingTokens.small)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) {
                                onDelete(bookmark.id)
                            } label: {
                                // Resolve "Delete" from Markly's module bundle, not the host's main bundle.
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
}