//
//  MarklyBlockSequence.swift
//  Markly
//
//  The block-stacking primitive. Renders `[MarklyBlock]` in a zero-spacing `VStack` and applies
//  a per-block *gap-before* padding from ``MarklyMarkdownTheme/topGap(for:tight:)``. The first
//  block gets no top gap (the page padding handles the leading edge). This "gap before each
//  block" model is what GitHub's markdown body effectively shows, it is `LazyVStack`-compatible
//  (no preference-key two-pass), and it composes recursively for tight containers (list items,
//  block quotes). See docs/Architecture.md §3, §10.
//
//  The list-nesting depth environment lives here too: nested lists read an incremented depth so
//  markers cycle disc → circle → square and content indents per level.
//

import SwiftUI
import Cosmos

/// Renders a sequence of markdown blocks with the gap-before spacing engine.
struct MarklyBlockSequence: View {
    /// The blocks to lay out, in order.
    let blocks: [MarklyBlock]
    /// `true` for sequences nested inside list items or block quotes (compact spacing).
    var tight: Bool = false

    @Environment(\.marklyMarkdownTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(blocks.enumerated()), id: \.element.id) { index, block in
                MarklyBlockView(block: block)
                    .padding(.top, index == 0 ? 0 : theme.topGap(for: block, tight: tight))
            }
        }
    }
}

// MARK: - List nesting depth

private struct MarklyListDepthKey: EnvironmentKey {
    static let defaultValue: Int = 0
}

extension EnvironmentValues {
    /// The current list-nesting depth (0 at the page root). `MarklyListView` increments it for
    /// nested list content so markers cycle and content indents.
    var marklyListDepth: Int {
        get { self[MarklyListDepthKey.self] }
        set { self[MarklyListDepthKey.self] = newValue }
    }
}