//
//  MarklyReaderView.swift
//  Markly
//
//  The reading surface: a `ScrollView` + `LazyVStack` of `MarklyBlockView`s. `LazyVStack`
//  keeps offscreen blocks unrendered for long books. `.scrollTargetLayout()` marks the
//  layout so paged mode can attach `.scrollTargetBehavior(.paging)` and a `scrollPosition`
//  binding could be added for reading-position persistence (see docs/Architecture.md §5).
//  A `ScrollViewReader` consumes the controller's `scrollRequest` (TOC / bookmark jumps).
//

import SwiftUI
import Cosmos

/// The scrollable reading surface that lays out a parsed document block-by-block.
struct MarklyReaderView: View {
    /// The parsed blocks to render.
    let blocks: [MarklyBlock]
    /// A pending scroll request from the controller (TOC / bookmark selection), or `nil`.
    let scrollRequest: MarklyReaderController.ScrollRequest?
    /// The reading mode (continuous scroll vs. paged).
    let readingMode: MarklyReadingMode

    @Environment(\.cosmosTheme) private var theme

    /// Page padding, scaled with Dynamic Type so accessibility text sizes keep generous margins
    /// rather than a fixed 32pt (Apple accessibility guidance for reading content).
    @ScaledMetric private var pagePadding: CGFloat = CosmosSpacingTokens.xxl

    var body: some View {
        ScrollViewReader { proxy in
            scrollingSurface
                .onChange(of: scrollRequest) { _, request in
                    guard let request else { return }
                    proxy.scrollTo(request.id, anchor: .top)
                }
        }
    }

    /// The scroll view, with `.scrollTargetBehavior(.paging)` applied only in paged mode so
    /// continuous reading keeps free scrolling. `.scrollTargetLayout()` is always on (the
    /// scroll-target layout is also what `ScrollViewReader.scrollTo` aligns to).
    @ViewBuilder private var scrollingSurface: some View {
        if readingMode == .paged {
            ScrollView { stack }
                .scrollTargetBehavior(.paging)
                .background(theme.colors.background)
        } else {
            ScrollView { stack }
                .background(theme.colors.background)
        }
    }

    private var stack: some View {
        LazyVStack(alignment: .leading, spacing: CosmosSpacingTokens.large) {
            ForEach(blocks, id: \.id) { block in
                MarklyBlockView(block: block)
            }
        }
        .scrollTargetLayout()
        .padding(pagePadding)
    }
}