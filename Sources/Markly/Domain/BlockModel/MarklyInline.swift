//
//  MarklyInline.swift
//  Markly
//
//  The pure inline model — the inline subset of CommonMark/GFM that Foundation's
//  `AttributedString(markdown:options:)` can render when parsed with
//  `.inlineOnlyPreservingWhitespace`. Block layout is owned by `MarklyBlock`; this enum
//  captures only inline runs.
//

import Foundation

/// A single inline markdown construct, modeled as a recursive value type.
public enum MarklyInline: Sendable, Equatable, Codable {
    /// A run of literal text.
    case text(String)
    /// A soft line break (renders as a space).
    case softBreak
    /// A hard line break (two trailing spaces or a backslash).
    case lineBreak
    /// Strongly emphasized (bold) content.
    case strong([MarklyInline])
    /// Emphasized (italic) content.
    case emphasis([MarklyInline])
    /// Strikethrough content.
    case strikethrough([MarklyInline])
    /// An inline code span.
    case inlineCode(String)
    /// A hyperlink with a destination and inline label content.
    case link(destination: String, inlines: [MarklyInline])
    /// An image with a source URL and alt text.
    case image(source: String, alt: String)
}