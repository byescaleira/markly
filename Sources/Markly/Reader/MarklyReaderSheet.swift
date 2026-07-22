//
//  MarklyReaderSheet.swift
//  Markly
//
//  The reader's slide-up sheet with three tabs: Contents (the TOC), Bookmarks, and Highlights.
//  Presented by `MarklyReader`. Selecting a row jumps to its section (via the controller's
//  `scrollTo`) and dismisses the sheet; bookmarks and highlights can be deleted from their context
//  menu.
//

import SwiftUI
import Cosmos

/// A three-tab reader sheet (Contents / Bookmarks / Highlights).
struct MarklyReaderSheet: View {
    /// The TOC entries.
    let entries: [MarklyTOCEntry]
    /// The current book's bookmarks.
    let bookmarks: [MarklyBookmark]
    /// The current book's highlights.
    let highlights: [MarklyHighlight]
    /// Returns the plain-text excerpt for a highlight (over its range in its section).
    let highlightExcerpt: (MarklyHighlight) -> String
    /// The section currently in view (highlighted in the TOC).
    let currentID: MarklySectionID?
    /// The tab to open the sheet on (Contents by default; the bottom-bar Highlights button opens
    /// `.highlights`).
    var initialTab: Tab = .contents
    /// Jump to a section (TOC, bookmark, or highlight selection).
    let onSelectSection: (MarklySectionID) -> Void
    /// Delete a bookmark.
    let onDeleteBookmark: (UUID) -> Void
    /// Delete a highlight.
    let onDeleteHighlight: (UUID) -> Void

    /// The sheet's three tabs (internal so `MarklyReader` can request a specific tab on present).
    enum Tab: String, CaseIterable, Hashable {
        case contents, bookmarks, highlights
    }

    @State private var tab: Tab = .contents
    @Environment(\.cosmosTheme) private var theme

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Reader Sections", selection: $tab) {
                    Text("Contents", bundle: .module).tag(Tab.contents)
                    Text("Bookmarks", bundle: .module).tag(Tab.bookmarks)
                    Text("Highlights", bundle: .module).tag(Tab.highlights)
                }
                .pickerStyle(.segmented)
                .padding(CosmosSpacingTokens.medium)

                switch tab {
                case .contents:
                    MarklyTOCView(entries: entries, currentID: currentID, onSelect: onSelectSection)
                case .bookmarks:
                    MarklyBookmarksView(
                        bookmarks: bookmarks,
                        onSelect: onSelectSection,
                        onDelete: onDeleteBookmark
                    )
                case .highlights:
                    MarklyHighlightsView(
                        highlights: highlights,
                        excerpt: highlightExcerpt,
                        onSelect: onSelectSection,
                        onDelete: onDeleteHighlight
                    )
                }
            }
            .navigationTitle(Text("Reader", bundle: .module))
            .toolbarTitleDisplayMode(.inline)
            .onAppear { tab = initialTab }
        }
        .presentationDetents([.medium, .large])
    }
}