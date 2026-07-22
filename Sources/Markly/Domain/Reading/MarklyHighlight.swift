//
//  MarklyHighlight.swift
//  Markly
//
//  A user-created multi-color highlight over a range of text in a book. Mirrors `MarklyBookmark`
//  (many per book, each with its own `UUID`) and is persisted the same way over a Nebula
//  repository. The highlight color set matches Apple Books' annotation styles (yellow, green,
//  blue, pink, purple + underline).
//
//  The highlight `range` is expressed as **character offsets into the block's flattened plain
//  text** — the same coordinate system `MarklySearch` uses for `matchOffset` — so a highlight is
//  stable across re-parses as long as the block's text content is unchanged. The SwiftUI `Color`
//  tint for each case lives in `Rendering/MarklyHighlightStyler.swift` (Domain stays
//  Foundation-only).
//

import Foundation
import Nebula

/// The color (or underline) of a highlight, matching Apple Books' annotation-style palette.
public enum MarklyHighlightColor: Int, Sendable, Equatable, Hashable, Codable, CaseIterable, Identifiable {
    /// An underline stroke (no background tint).
    case underline = 0
    /// Green.
    case green = 1
    /// Blue.
    case blue = 2
    /// Yellow (the default highlight color).
    case yellow = 3
    /// Pink.
    case pink = 4
    /// Purple.
    case purple = 5

    /// Identifiable id (the raw annotation-style int).
    public var id: Int { rawValue }

    /// The five marker colors in Apple Books' palette order (yellow, green, blue, pink, purple),
    /// excluding underline.
    public static var markerColors: [MarklyHighlightColor] {
        [.yellow, .green, .blue, .pink, .purple]
    }

    /// `true` for the underline style (drawn as a bottom stroke, not a background tint).
    public var isUnderline: Bool { self == .underline }
}

/// A multi-color highlight over a range of text in a book.
public struct MarklyHighlight: NebulaEntity, Codable, Sendable, Equatable, Identifiable {
    public typealias ID = UUID
    /// The highlight's unique id.
    public let id: UUID
    /// The book this highlight belongs to.
    public let bookID: UUID
    /// The section (block) the highlight is anchored to.
    public let sectionID: MarklySectionID
    /// Character range into the block's flattened plain text (same coordinate as `MarklySearch`
    /// match offsets).
    public var range: Range<Int>
    /// The highlight color.
    public var color: MarklyHighlightColor
    /// An optional user note attached to the highlight.
    public var note: String?
    /// When the highlight was created.
    public let createdAt: Date

    /// Creates a highlight.
    public init(
        id: UUID = UUID(),
        bookID: UUID,
        sectionID: MarklySectionID,
        range: Range<Int>,
        color: MarklyHighlightColor,
        note: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.bookID = bookID
        self.sectionID = sectionID
        self.range = range
        self.color = color
        self.note = note
        self.createdAt = createdAt
    }
}