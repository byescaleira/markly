//
//  MarklyInlineText.swift
//  Markly
//
//  Renders `[MarklyInline]` as styled, tappable `Text` by re-serializing the inlines back to a
//  markdown string and parsing it through Foundation's `AttributedString(markdown:options:)`
//  with `.inlineOnlyPreservingWhitespace`. This is the v1 correctness-first path: Apple's
//  parser handles every inline edge case (nested emphasis, code spans, autolinks,
//  strikethrough, image alt). CosmosText/CosmosLabel have no `AttributedString` initializer
//  (only `String`/verbatim), so inline markdown must route through native `Text`.
//
//  Images are the one inline SwiftUI `Text` cannot draw: `AttributedString(markdown:)` parses
//  `![alt](url)` into an image attachment, but `Text(attributedString)` renders only the alt
//  text. So when inlines contain an image, this view splits into text runs (still rendered as
//  one `Text` via `AttributedString`) and images (rendered as `CosmosAsyncImage`). The no-image
//  path is unchanged — a single `Text` — so all call-site modifiers (`.font`, `.lineSpacing`,
//  `.accessibilityHeading`, …) keep their original semantics for the common case.
//  See docs/Architecture.md §3, §10.
//

import SwiftUI
import Cosmos

/// Renders a run of inline markdown as styled, tappable `Text`, with images rendered inline.
struct MarklyInlineText: View {
    /// The inline content to render.
    let inlines: [MarklyInline]

    /// Inline-only parsing that preserves whitespace (so prose spacing survives).
    private static let options = AttributedString.MarkdownParsingOptions(
        allowsExtendedAttributes: true,
        interpretedSyntax: .inlineOnlyPreservingWhitespace,
        failurePolicy: .returnPartiallyParsedIfPossible
    )

    var body: some View {
        if inlines.contains(where: { if case .image = $0 { return true }; return false }) {
            MarklyRichInlineContent(inlines: inlines)
        } else if let attributed = Self.render(inlines) {
            Text(attributed)
        } else {
            // Parsing failed: fall back to the literal serialized markdown as plain text.
            Text(verbatim: MarklyInlineSerializer.toMarkdown(inlines))
        }
    }

    /// Serializes inlines to markdown and parses them to an `AttributedString`.
    fileprivate static func render(_ inlines: [MarklyInline]) -> AttributedString? {
        let markdown = MarklyInlineSerializer.toMarkdown(inlines)
        return try? AttributedString(markdown: markdown, options: options, baseURL: nil)
    }
}

/// Renders inlines that contain at least one image. Text-bearing runs are concatenated into a
/// single `AttributedString`-backed `Text`; each image becomes a `CosmosAsyncImage` with its alt
/// text as the accessibility label. Markdown images here behave block-level (stacked), which is
/// the natural reading layout and avoids SwiftUI `Text`'s inability to draw inline attachments.
private struct MarklyRichInlineContent: View {
    let inlines: [MarklyInline]

    var body: some View {
        VStack(alignment: .leading, spacing: CosmosSpacingTokens.small) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                switch segment {
                case .text(let runs):
                    if let attributed = MarklyInlineText.render(runs) {
                        Text(attributed)
                    } else {
                        Text(verbatim: MarklyInlineSerializer.toMarkdown(runs))
                    }
                case .image(let source, let alt):
                    CosmosAsyncImage(url: URL(string: source)) { image in
                        image
                            .resizable()
                            .scaledToFit()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel(alt)
                }
            }
        }
    }

    private enum Segment {
        case text([MarklyInline])
        case image(source: String, alt: String)
    }

    /// Splits the inlines into maximal text runs separated by images.
    private var segments: [Segment] {
        var out: [Segment] = []
        var textRun: [MarklyInline] = []
        for inline in inlines {
            if case let .image(source, alt) = inline {
                if !textRun.isEmpty { out.append(.text(textRun)); textRun = [] }
                out.append(.image(source: source, alt: alt))
            } else {
                textRun.append(inline)
            }
        }
        if !textRun.isEmpty { out.append(.text(textRun)) }
        return out
    }
}