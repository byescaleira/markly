//
//  MarklyBook.swift
//  Markly
//
//  The source a host app implements to give Markly a markdown document. `MarklyLiteralBook`
//  covers the common in-memory case. Markly parses the source once and caches the block
//  model keyed by the book's `id`.
//

import Foundation

/// A markdown document that Markly can render.
public protocol MarklyBook: Sendable, Identifiable where ID == UUID {
    /// The stable identity of the book.
    var id: UUID { get }
    /// The display title of the book.
    var title: String { get }
    /// The author of the book, if known.
    var author: String? { get }
    /// The markdown source. Markly parses it once and caches the block model.
    func source() async throws -> String
}

/// A value-backed `MarklyBook` whose source is a literal markdown string. Covers the common
/// in-memory case; implement `MarklyBook` directly for file/URL/database-backed books.
public struct MarklyLiteralBook: MarklyBook {
    public let id: UUID
    public let title: String
    public let author: String?
    private let sourceText: String

    /// Creates a literal book from a markdown string.
    public init(
        id: UUID = UUID(),
        title: String,
        markdown: String,
        author: String? = nil
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.sourceText = markdown
    }

    public func source() async throws -> String {
        sourceText
    }
}