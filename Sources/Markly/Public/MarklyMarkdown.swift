//
//  MarklyMarkdown.swift
//  Markly
//
//  A chrome-less markdown body view — the rendering engine of ``MarklyReader`` without the
//  e-reader surface (no `NavigationStack`, toolbar, bottom bar, sheets, brightness, bookmarks,
//  highlights, or reading-position persistence). It parses the markdown through the same
//  instrumented ``MarklyParse`` use case and renders the same ``MarklyBlockSequence`` (gap-before
//  engine + MarkdownUI theme/code-block/image providers) the reader uses, so a fragment of
//  markdown — a forum post body, a comment, a description — renders identically to the reader
//  but embeds inline in a host's own scroll/layout hierarchy.
//
//  Use this when you want markdown *rendering* without the reader *chrome*: a post body inside
//  an existing `NavigationStack`/`ScrollView`, where nesting a full ``MarklyReader`` would
//  double the nav bar and nest scroll views. For the full reading experience (TOC, bookmarks,
//  highlights, aA, share, position), use ``MarklyReader``.
//
//  Paragraphs render through the non-selectable `Text` path (features forced to ``MarklyFeatures/none``),
//  so there is no text-selection/highlight surface — appropriate for an inline, read-only body.
//
//     MarklyMarkdown(post.body ?? "")
//     MarklyMarkdown("# Hello\n\nA paragraph with **bold** and `code`.")
//

import SwiftUI
import Cosmos
import MarkdownUI

/// A chrome-less markdown body view — renders a markdown string inline, without the e-reader
/// surface. Parses via ``MarklyParse`` and renders via the same block engine as ``MarklyReader``.
public struct MarklyMarkdown: View {
    /// The markdown source to render. Re-parsing is keyed on this value (`.task(id:)`), so
    /// changing it re-parses instead of leaving the prior content on screen.
    private let markdown: String
    /// The font-size step applied to the SwiftUI `Text`-based blocks via `.dynamicTypeSize`
    /// (independent of the system Dynamic Type setting, like Apple Books). Defaults to
    /// ``MarklyFontSize/default``.
    private let fontSize: MarklyFontSize

    @Environment(\.cosmosTheme) private var theme
    @State private var blocks: [MarklyBlock] = []

    /// Creates a chrome-less markdown body view.
    /// - Parameters:
    ///   - markdown: The markdown source to render.
    ///   - fontSize: The reader's discrete font-size step (defaults to ``MarklyFontSize/default``).
    public init(_ markdown: String, fontSize: MarklyFontSize = .default) {
        self.markdown = markdown
        self.fontSize = fontSize
    }

    public var body: some View {
        // `Group` gives the chain a concrete `View` type so `.task(id:)` resolves; a bare `if`
        // without `else` yields an optional view whose type the modifier lookup can't pin.
        Group {
            // Nothing to render until the (fast, off-main) parse resolves. An empty markdown
            // string parses to an empty block list and renders nothing — correct for a body-less post.
            if !blocks.isEmpty {
                MarklyBlockSequence(blocks: blocks)
                    // Drive every SwiftUI `Text`-based block from the font-size step (mirrors the
                    // reader; MarkdownUI's `ScaledFontSizeModifier` also reads `.dynamicTypeSize`).
                    .dynamicTypeSize(fontSize.dynamicTypeSize)
                    // Style the MarkdownUI-rendered blocks (headings, code, rules, HTML) with the
                    // GitHub layout driven by the host's Cosmos color tokens — adapts to the host
                    // theme, no reader paper-style override.
                    .markdownTheme(MarklyMarkdownUITheme.theme(colors: theme.colors))
                    .markdownBlockStyle(\.codeBlock) { configuration in
                        MarklyCodeBlockCard(
                            label: configuration.label,
                            language: configuration.language,
                            code: configuration.content
                        )
                    }
                    .markdownInlineImageProvider(.markly)
                    .markdownCodeSyntaxHighlighter(.plainText)
                    // Force the reader features off so paragraphs take the non-selectable `Text` path
                    // (no highlight/selection surface) — the right default for an inline, read-only
                    // body. The font-size step is pushed in so any `Text`-based block scales.
                    .environment(\.marklyReaderFeatures, .none)
                    .environment(\.marklyReaderFontSize, fontSize)
            }
        }
        .task(id: markdown) { await parse() }
    }

    /// Parses `markdown` into `[MarklyBlock]` through the instrumented use case (detached off-main,
    /// measured/reported). The body is total in practice; `try?` guards the throw contract.
    @MainActor
    private func parse() async {
        let parsed = try? await MarklyParse.useCase.executeTyped(MarklyParseInput(source: markdown))
        blocks = parsed?.blocks ?? []
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        MarklyMarkdown(
            """
            # A chrome-less body

            A paragraph with **bold**, *italic*, ~~struck~~, `code`, and a [link](https://example.com).

            ## Code

            ```swift
            let x = 42
            ```

            ## List

            1. First
            2. Second

            > A block quote.
            """
        )
        .padding()
    }
    .environment(\.cosmosTheme, CosmosTheme.default)
}