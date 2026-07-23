//
//  MarklyInlineText.swift
//
//  Renders `[MarklyInline]` as styled, tappable `Text` by re-serializing the inlines back to a
//  markdown string and parsing it through Foundation's `AttributedString(markdown:options:)`
//  with `.inlineOnlyPreservingWhitespace`. This is the v1 correctness-first path: Apple's
//  parser handles every inline edge case (nested emphasis, code spans, autolinks,
//  strikethrough, image alt). CosmosText/CosmosLabel have no `AttributedString` initializer
//  (only `String`/verbatim), so inline markdown must route through native `Text`.
//
//  Font ownership: this view owns its base font (`baseSize` + `weight`, Dynamic-Type-scaled via
//  `@ScaledMetric`) so callers don't apply a separate `.font`. Inline-code runs are special-cased:
//  SwiftUI renders AttributedString `.code` runs with a monospaced font that bypasses the view's
//  `.font` modifier, so a code span inside a heading or semibold table header would otherwise
//  render at the default body monospaced size. We set an explicit monospaced font on each `.code`
//  run, matched to the surrounding size/weight, so code spans scale with headings/headers.
//
//  Images are the one inline SwiftUI `Text` cannot draw: `AttributedString(markdown:)` parses
//  `![alt](url)` into an image attachment, but `Text(attributedString)` renders only the alt
//  text. So when inlines contain an image *anywhere* (recursively — including the common
//  linked-image `[![alt](url)](link)` and `**![alt](url)**` patterns), this view delegates to
//  `MarklyRichInlineContent`, which splits the inlines into text runs (still `Text` via
//  `AttributedString`) and images (`MarklyRemoteImage`). The no-image path is a single `Text`.
//  See docs/Architecture.md §3, §10.
//

import SwiftUI
import Cosmos

/// Renders a run of inline markdown as styled, tappable `Text`, with images rendered inline.
struct MarklyInlineText: View {
    /// The inline content to render.
    let inlines: [MarklyInline]
    /// Base body point size for the text (scaled with Dynamic Type).
    let baseSize: CGFloat
    /// Font weight of the surrounding text.
    let weight: Font.Weight

    /// Dynamic-Type-scaled base size (reads the reader's `.dynamicTypeSize` environment).
    @ScaledMetric private var scaledSize: CGFloat

    /// Inline-only parsing that preserves whitespace (so prose spacing survives).
    private static let options = AttributedString.MarkdownParsingOptions(
        allowsExtendedAttributes: true,
        interpretedSyntax: .inlineOnlyPreservingWhitespace,
        failurePolicy: .returnPartiallyParsedIfPossible
    )

    init(
        inlines: [MarklyInline],
        baseSize: CGFloat = CosmosTextStyle.body.pointSize,
        weight: Font.Weight = .regular
    ) {
        self.inlines = inlines
        self.baseSize = baseSize
        self.weight = weight
        _scaledSize = ScaledMetric(wrappedValue: baseSize, relativeTo: .body)
    }

    var body: some View {
        if Self.containsImage(inlines) {
            MarklyRichInlineContent(inlines: inlines)
        } else if let attributed = Self.render(inlines, codeFont: codeFont) {
            Text(attributed)
                .font(.system(size: scaledSize, weight: weight))
        } else {
            // Parsing failed: fall back to the literal serialized markdown as plain text.
            Text(verbatim: MarklyInlineSerializer.toMarkdown(inlines))
                .font(.system(size: scaledSize, weight: weight))
        }
    }

    /// The monospaced font for inline-code runs, matched to the surrounding text size/weight so
    /// code spans inside headings/headers don't render at the default body monospaced size.
    private var codeFont: Font {
        .system(size: scaledSize, weight: weight, design: .monospaced)
    }

    /// Serializes inlines to markdown and parses them to an `AttributedString`. When `codeFont` is
    /// supplied, every `.code` run is given that explicit font (overriding SwiftUI's default
    /// monospaced code rendering, which ignores the view's `.font` modifier).
    fileprivate static func render(_ inlines: [MarklyInline], codeFont: Font? = nil) -> AttributedString? {
        let markdown = MarklyInlineSerializer.toMarkdown(inlines)
        guard var attributed = try? AttributedString(markdown: markdown, options: options, baseURL: nil) else {
            return nil
        }
        if let codeFont {
            for run in attributed.runs where run.inlinePresentationIntent?.contains(.code) == true {
                attributed[run.range].font = codeFont
            }
        }
        return attributed
    }

    /// `true` if the inlines contain an image anywhere (recursively — through strong, emphasis,
    /// strikethrough, and link containers). Mirrors `MarklyBlockView`'s paragraph-routing check.
    static func containsImage(_ inlines: [MarklyInline]) -> Bool {
        for inline in inlines {
            switch inline {
            case .image:
                return true
            case .strong(let inner), .emphasis(let inner), .strikethrough(let inner):
                if containsImage(inner) { return true }
            case .link(_, let inner):
                if containsImage(inner) { return true }
            default:
                break
            }
        }
        return false
    }
}

/// Renders inlines that contain at least one image (recursively). Text-bearing runs are rendered
/// as `AttributedString`-backed `Text`; each image becomes a `MarklyRemoteImage` with its alt text
/// as the accessibility label. Markdown images here behave block-level (stacked), which is the
/// natural reading layout and avoids SwiftUI `Text`'s inability to draw inline attachments.
private struct MarklyRichInlineContent: View {
    let inlines: [MarklyInline]

    var body: some View {
        VStack(alignment: .leading, spacing: CosmosSpacingTokens.small) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                switch segment {
                case .text(let runs):
                    // Image-free text runs render through `MarklyInlineText` so they pick up the
                    // body font and inline-code sizing consistently.
                    MarklyInlineText(inlines: runs)
                case .image(let source, let alt):
                    MarklyRemoteImage(source: source, alt: alt)
                }
            }
        }
    }

    private enum Segment {
        case text([MarklyInline])
        case image(source: String, alt: String)
    }

    /// Splits the inlines into maximal text runs separated by images, recursing into strong /
    /// emphasis / strikethrough / link containers so a nested image (e.g. a linked image
    /// `[![alt](url)](link)`) is extracted and its sibling content keeps its container styling.
    private var segments: [Segment] {
        var out: [Segment] = []
        var textRun: [MarklyInline] = []
        func flush() {
            if !textRun.isEmpty {
                out.append(.text(textRun))
                textRun.removeAll(keepingCapacity: true)
            }
        }
        /// Returns the inlines with all images (recursively) removed, emitting each image as a
        /// `.image` segment in encounter order (flushing the surrounding text first). Containers
        /// that lose their image are rebuilt with the remaining children so their styling survives.
        func strip(_ inlines: [MarklyInline]) -> [MarklyInline] {
            var kept: [MarklyInline] = []
            for inline in inlines {
                switch inline {
                case .image(let source, let alt):
                    flush()
                    out.append(.image(source: source, alt: alt))
                case .strong(let inner):
                    let stripped = strip(inner)
                    if !stripped.isEmpty { kept.append(.strong(stripped)) }
                case .emphasis(let inner):
                    let stripped = strip(inner)
                    if !stripped.isEmpty { kept.append(.emphasis(stripped)) }
                case .strikethrough(let inner):
                    let stripped = strip(inner)
                    if !stripped.isEmpty { kept.append(.strikethrough(stripped)) }
                case .link(let destination, let inner):
                    let stripped = strip(inner)
                    if !stripped.isEmpty { kept.append(.link(destination: destination, inlines: stripped)) }
                case .text, .softBreak, .lineBreak, .inlineCode:
                    kept.append(inline)
                }
            }
            return kept
        }
        let remaining = strip(inlines)
        if !remaining.isEmpty { textRun.append(contentsOf: remaining) }
        flush()
        return out
    }
}