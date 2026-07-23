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
    @Environment(\.marklyMarkdownTheme) private var md
    /// The reader's font-size step. Applied to the SwiftUI `Text`-based blocks (headings, non-
    /// selectable paragraphs, list markers, code, tables) via `.dynamicTypeSize` so the aA font-size
    /// slider scales them — independent of the system Dynamic Type setting, mirroring Apple Books.
    /// The selectable `UITextView`/`NSTextView` paragraphs scale separately via `fontSize.scale`
    /// (UIKit/AppKit text views don't read the `.dynamicTypeSize` environment), so this does not
    /// double-scale them.
    @Environment(\.marklyReaderFontSize) private var fontSize

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
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(Array(blocks.enumerated()), id: \.element.id) { index, block in
                MarklyBlockView(block: block)
                    .padding(.top, index == 0 ? 0 : md.topGap(for: block, tight: false))
            }
        }
        .scrollTargetLayout()
        .padding(pagePadding)
        // Drive every SwiftUI `Text`-based block from the reader's font-size step (independent of
        // the system Dynamic Type setting, like Apple Books). The selectable text views are
        // unaffected (they size via `fontSize.scale`, not this environment).
        .dynamicTypeSize(fontSize.dynamicTypeSize)
    }
}