//
//  MarklyBookmark.swift
//  Markly
//
//  A user-created bookmark: a named pointer to a section of a book. Many bookmarks per book, each
//  with its own `UUID`. An aggregate root over Nebula's `NebulaEntity` marker; `Codable` so the
//  `NebulaPreferences`-backed repository can JSON-encode the collection.
//

import Foundation
import Nebula

/// A bookmark pointing at a section of a book.
public struct MarklyBookmark: NebulaEntity, Codable, Sendable, Equatable, Identifiable {
    public typealias ID = UUID
    /// The bookmark's unique id.
    public let id: UUID
    /// The book this bookmark belongs to.
    public let bookID: UUID
    /// The section the bookmark points at.
    public let sectionID: MarklySectionID
    /// A human-readable label (usually the heading text).
    public let title: String
    /// When the bookmark was created.
    public let createdAt: Date

    /// Creates a bookmark.
    public init(
        id: UUID = UUID(),
        bookID: UUID,
        sectionID: MarklySectionID,
        title: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.bookID = bookID
        self.sectionID = sectionID
        self.title = title
        self.createdAt = createdAt
    }
}