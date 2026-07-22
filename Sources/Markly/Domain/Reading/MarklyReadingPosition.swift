//
//  MarklyReadingPosition.swift
//  Markly
//
//  A persisted reading position: which section of which book the reader last reached. One
//  position per book, so the entity's `id` is the book's `UUID` — `find(id: book.id)` returns
//  the position for that book and `save` upserts it. An aggregate root over Nebula's
//  `NebulaEntity` marker; `Codable` so the `NebulaPreferences`-backed repository can JSON-encode it.
//

import Foundation
import Nebula

/// The last-read section of a book, persisted so the reader can restore it on reopen.
public struct MarklyReadingPosition: NebulaEntity, Codable, Sendable, Equatable {
    /// `id` is the book's `UUID` (one position per book), so the repository's `find(id:)` /
    /// `save(_:)` directly key by book without a separate query.
    public typealias ID = UUID
    public let id: UUID
    /// The section the reader was last on.
    public let sectionID: MarklySectionID
    /// When the position was last saved.
    public let updatedAt: Date

    /// Creates a reading position. `id` is the book's `UUID`.
    public init(id: UUID, sectionID: MarklySectionID, updatedAt: Date = Date()) {
        self.id = id
        self.sectionID = sectionID
        self.updatedAt = updatedAt
    }
}