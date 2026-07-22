//
//  MarklySearchView.swift
//  Markly
//
//  In-document search UI presented as a sheet: a search field + a live, debounced results list
//  over the parsed blocks. Scanning runs off the main actor (`[MarklyBlock]` is `Sendable` and
//  `MarklySearch.results(for:in:options:)` is pure), so the UI stays responsive while the user
//  types. Each result shows its enclosing section title and a windowed snippet with the match
//  highlighted; tapping a result scrolls the reader there (via `onSelect` →
//  `MarklyReaderController.scrollTo`).
//
//  The field uses a native `TextField` (consistent with Markly's v0.1 chrome); adopting the
//  `CosmosTextField` atom is a backlog item (see docs/Architecture.md §9). Recovery verbs are
//  localized via `Bundle.module`.
//

import SwiftUI
import Cosmos

/// A sheet that searches the parsed document and lists matches with highlighted snippets.
struct MarklySearchView: View {
    /// The parsed blocks to search.
    let blocks: [MarklyBlock]
    /// Called with a result's scroll target when the user taps a match.
    let onSelect: (MarklySectionID) -> Void

    @Environment(\.cosmosTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var results: [MarklySearchResult] = []
    @State private var searching = false

    private let debouncer = MarklySearchDebouncer()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TextField(
                    "",
                    text: $query,
                    prompt: Text("Search this book", bundle: .module)
                )
                #if !os(tvOS)
                .textFieldStyle(.roundedBorder)
                #endif
                .padding(CosmosSpacingTokens.medium)

                Divider()

                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle(Text("Search", bundle: .module))
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Text("Done", bundle: .module)
                    }
                }
            }
        }
        // Re-run (debounced) whenever the query changes; the debouncer hops off-main and
        // cancels stale scans so only the latest query's results land.
        .task(id: query) {
            let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !needle.isEmpty else {
                results = []
                searching = false
                return
            }
            searching = true
            let matches = await debouncer.run(needle, blocks: blocks)
            results = matches
            searching = false
        }
    }

    @ViewBuilder private var content: some View {
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            MarklySearchEmptyState(message: Text("Search this book", bundle: .module))
        } else if searching {
            CosmosProgress()
                .frame(width: 32, height: 32)
        } else if results.isEmpty {
            MarklySearchEmptyState(message: Text("No search results", bundle: .module))
        } else {
            List(results) { result in
                Button {
                    onSelect(result.sectionID)
                    dismiss()
                } label: {
                    MarklySearchResultRow(result: result)
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
        }
    }
}

/// A single search-result row: the enclosing section title and a highlighted snippet.
private struct MarklySearchResultRow: View {
    let result: MarklySearchResult

    @Environment(\.cosmosTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: CosmosSpacingTokens.xs) {
            Text(result.sectionTitle)
                .font(.headline)
                .foregroundStyle(theme.colors.primary)
                .lineLimit(1)
            highlightedSnippet
                .font(.subheadline)
                .foregroundStyle(theme.colors.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, CosmosSpacingTokens.xs)
        .accessibilityElement(children: .combine)
    }

    /// The snippet with the matched substring rendered in the accent color + semibold.
    private var highlightedSnippet: Text {
        var attr = AttributedString(result.snippet)
        guard !result.snippet.isEmpty,
              result.matchRange.lowerBound >= 0,
              result.matchRange.upperBound <= result.snippet.count,
              result.matchRange.lowerBound <= result.matchRange.upperBound
        else {
            return Text(attr)
        }
        let lower = attr.index(attr.startIndex, offsetByCharacters: result.matchRange.lowerBound)
        let upper = attr.index(attr.startIndex, offsetByCharacters: result.matchRange.upperBound)
        attr[lower..<upper].foregroundColor = theme.colors.accent
        return Text(attr)
    }
}

/// The empty/placeholder state for the search list.
private struct MarklySearchEmptyState: View {
    let message: Text

    @Environment(\.cosmosTheme) private var theme

    var body: some View {
        VStack(spacing: CosmosSpacingTokens.small) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 32))
                .foregroundStyle(theme.colors.secondary)
            message
                .foregroundStyle(theme.colors.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Hops the (pure, CPU-bound) scan off the main actor with a small debounce so rapid keystrokes
/// don't trigger a scan per key. Stateless; safe to share across the `.task(id:)`.
private struct MarklySearchDebouncer: Sendable {
    func run(_ query: String, blocks: [MarklyBlock]) async -> [MarklySearchResult] {
        // A short settle delay cancels stale scans: the `.task(id: query)` cancels the prior
        // task on the next keystroke, aborting this sleep before the scan runs.
        try? await Task.sleep(for: .milliseconds(150))
        if Task.isCancelled { return [] }
        return await Task.detached(priority: .userInitiated) {
            MarklySearch.results(for: query, in: blocks)
        }.value
    }
}