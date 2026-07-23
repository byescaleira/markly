//
//  MarklyMarkdownUITheme.swift
//
//  Builds the MarkdownUI `Theme` that styles the blocks Markly routes through the vendored
//  MarkdownUI renderer (headings, code blocks, thematic breaks, HTML blocks). The block layouts
//  are GitHub's; the colors are Cosmos color tokens, so the MarkdownUI-rendered blocks adapt to
//  the reader's paper style (light / sepia / dark) exactly like Markly's own blocks.
//
//  The block-style closures themselves live in the MarkdownUI target (Swift 5) — see
//  `Theme+Markly.swift` for why. This file only calls that builder with Cosmos-derived colors and
//  is plain Swift 6. The code-block style is overridden separately, at the view tree, with
//  `MarklyCodeBlockCard` (Markly's Copy-button card wrapping MarkdownUI's code label).
//  See docs/Architecture.md §3, §10.
//

import SwiftUI
import Cosmos
import MarkdownUI

/// Maps Cosmos color tokens onto a MarkdownUI `Theme` (GitHub layouts, Cosmos palette).
enum MarklyMarkdownUITheme {

    /// Builds a MarkdownUI `Theme` driven by the given Cosmos color tokens.
    static func theme(colors: CosmosColorTokens) -> Theme {
        Theme.marklyGitHub(
            text: colors.primary,
            secondaryText: colors.secondary,
            tertiaryText: colors.secondary,
            background: colors.background,
            secondaryBackground: colors.surface,
            link: colors.accent,
            border: colors.outline,
            divider: colors.outline
        )
    }
}