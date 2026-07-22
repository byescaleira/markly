//
//  MarklyInlineSerializer.swift
//  Markly
//
//  Re-serializes `[MarklyInline]` back to a markdown string so Foundation's
//  `AttributedString(markdown:options:)` can parse the inline subset. This is the v1
//  correctness-first path: Apple's parser handles every inline edge case (nested emphasis,
//  code spans, autolinks, strikethrough, image alt). A direct `AttributedString` builder
//  walking `MarklyInline` and applying `AttributeContainer` runs is the deferred v2
//  optimization, kept behind the same `MarklyInlineText` renderer type (see §3, §10).
//

import Foundation

/// Serializes Markly's inline model back to a markdown string.
public enum MarklyInlineSerializer {

    /// Serializes a list of inlines to a markdown string.
    public static func toMarkdown(_ inlines: [MarklyInline]) -> String {
        var output = ""
        for inline in inlines {
            output.append(serialize(inline))
        }
        return output
    }

    private static func serialize(_ inline: MarklyInline) -> String {
        switch inline {
        case .text(let text):
            return escape(text)
        case .softBreak:
            return "\n"
        case .lineBreak:
            // A hard break: two trailing spaces followed by a newline.
            return "  \n"
        case .strong(let inner):
            return "**" + toMarkdown(inner) + "**"
        case .emphasis(let inner):
            return "*" + toMarkdown(inner) + "*"
        case .strikethrough(let inner):
            return "~~" + toMarkdown(inner) + "~~"
        case .inlineCode(let code):
            // Use fenced code span with double backticks when the code itself contains a
            // backtick, to keep the span balanced.
            if code.contains("`") {
                return "`` " + code + " ``"
            }
            return "`" + code + "`"
        case .link(let destination, let inner):
            return "[" + toMarkdown(inner) + "](" + wrapDestination(destination) + ")"
        case .image(let source, let alt):
            return "![" + escape(alt) + "](" + wrapDestination(source) + ")"
        }
    }

    /// Renders a link/image destination, angle-wrapping it when it contains characters that are
    /// unsafe in a bare destination (`)`, `(`, or whitespace). A bare `[label](a)b)` truncates at
    /// the first `)` on reparse; `<a)b>` round-trips through both swift-markdown and Foundation.
    /// Destinations containing `>` cannot be safely angle-wrapped and are left bare (rare).
    private static func wrapDestination(_ dest: String) -> String {
        let needsWrapping = dest.contains(")") || dest.contains("(") || dest.contains(" ")
        guard needsWrapping, !dest.contains(">") else { return dest }
        return "<\(dest)>"
    }

    /// Escapes markdown punctuation in literal text so it round-trips through the parser
    /// as plain text rather than being interpreted as syntax. `~` is included so a literal
    /// double-tilde (`~~`) in text is not reinterpreted as GFM strikethrough on the inline reparse.
    private static func escape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "*", with: "\\*")
            .replacingOccurrences(of: "_", with: "\\_")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "[", with: "\\[")
            .replacingOccurrences(of: "]", with: "\\]")
            .replacingOccurrences(of: "!", with: "\\!")
            .replacingOccurrences(of: "~", with: "\\~")
    }
}