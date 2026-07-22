//
//  MarklyReadingRepositories.swift
//  Markly
//
//  Repository seams for reading-position, bookmarks, and highlights, layered on Nebula's
//  repository protocols (`NebulaKeyedRepository` / `NebulaWritableRepository` /
//  `NebulaDeletableRepository`). Nebula ships no concrete persistent repository, so Markly
//  provides a zero-config `MarklyPreferencesRepository` backed by `NebulaPreferences` (JSON in
//  `UserDefaults`) — enough for an e-reader's small collections (one position per book; dozens of
//  bookmarks/highlights). A host that needs scale conforms its own seams over SwiftData/Core Data.
//  Tests/previews use Nebula's shipped `NebulaFakeRepository`.
//

import Foundation
import Nebula

/// Persistence seam for `MarklyReadingPosition` (Nebula keyed/writable/deletable capabilities).
public protocol MarklyReadingPositionRepository:
    NebulaKeyedRepository, NebulaWritableRepository, NebulaDeletableRepository
    where Element == MarklyReadingPosition {}

/// Persistence seam for `MarklyBookmark` (Nebula keyed/writable/deletable capabilities).
public protocol MarklyBookmarkRepository:
    NebulaKeyedRepository, NebulaWritableRepository, NebulaDeletableRepository
    where Element == MarklyBookmark {}

/// Persistence seam for `MarklyHighlight` (Nebula keyed/writable/deletable capabilities).
public protocol MarklyHighlightRepository:
    NebulaKeyedRepository, NebulaWritableRepository, NebulaDeletableRepository
    where Element == MarklyHighlight {}

/// A zero-config repository backed by `NebulaPreferences`: stores the whole collection as a
/// JSON array under one key. Stateless (reads/writes the store on every call), so it is
/// `Sendable`. Suitable for small collections; a host with many entries should swap in a
/// SwiftData/Core-Data-backed `MarklyReadingPositionRepository` / `MarklyBookmarkRepository` /
/// `MarklyHighlightRepository`.
public final class MarklyPreferencesRepository<Entity: NebulaEntity & Codable>:
    NebulaKeyedRepository, NebulaWritableRepository, NebulaDeletableRepository
where Entity.ID == UUID {
    public typealias Element = Entity

    private let prefs: NebulaPreferences
    private let key: String

    /// Creates a repository backed by the given preferences store, storing the collection under
    /// `key`.
    public init(prefs: NebulaPreferences, key: String) {
        self.prefs = prefs
        self.key = key
    }

    public func find(id: UUID) async throws -> Entity? {
        try load().first { $0.id == id }
    }

    public func stream() -> AsyncThrowingStream<Entity, any Error> {
        AsyncThrowingStream { continuation in
            do {
                for entity in try load() { continuation.yield(entity) }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }

    public func count() async throws -> Int {
        try load().count
    }

    public func save(_ entity: Entity) async throws {
        var all = try load()
        all.removeAll { $0.id == entity.id }
        all.append(entity)
        try store(all)
    }

    public func delete(_ id: UUID) async throws {
        var all = try load()
        all.removeAll { $0.id == id }
        try store(all)
    }

    private func load() throws -> [Entity] {
        do {
            return try prefs.value([Entity].self, forKey: key) ?? []
        } catch {
            // A corrupt/decodable failure shouldn't fatal the reader: drop the collection.
            return []
        }
    }

    private func store(_ entities: [Entity]) throws {
        try prefs.setValue(entities, forKey: key)
    }
}

// MARK: - Markly-typed conformance

extension MarklyPreferencesRepository: MarklyReadingPositionRepository where Entity == MarklyReadingPosition {}
extension MarklyPreferencesRepository: MarklyBookmarkRepository where Entity == MarklyBookmark {}
extension MarklyPreferencesRepository: MarklyHighlightRepository where Entity == MarklyHighlight {}

// Nebula's in-memory fake conforms to Markly's repository seams for tests/previews. The protocol
// is Markly's (same module), so this is a normal conformance, not `@retroactive`.
extension NebulaFakeRepository: MarklyReadingPositionRepository where Element == MarklyReadingPosition {}
extension NebulaFakeRepository: MarklyBookmarkRepository where Element == MarklyBookmark {}
extension NebulaFakeRepository: MarklyHighlightRepository where Element == MarklyHighlight {}

// MARK: - Zero-config factories

/// Namespace for Markly's default (UserDefaults-backed) repositories.
public enum MarklyDefaultRepositories {
    /// Shared preferences store backed by `UserDefaults.standard`. `NebulaDefaults(_:)` takes the
    /// defaults `sending`, so this factory owns the only reference.
    public static let preferences: NebulaPreferences = NebulaDefaults(UserDefaults.standard)

    /// A zero-config reading-position repository (one position per book).
    public static func readingPositionRepository(
        prefs: NebulaPreferences = preferences
    ) -> any MarklyReadingPositionRepository {
        MarklyPreferencesRepository<MarklyReadingPosition>(prefs: prefs, key: "markly.readingPositions")
    }

    /// A zero-config bookmark repository.
    public static func bookmarkRepository(
        prefs: NebulaPreferences = preferences
    ) -> any MarklyBookmarkRepository {
        MarklyPreferencesRepository<MarklyBookmark>(prefs: prefs, key: "markly.bookmarks")
    }

    /// A zero-config highlight repository.
    public static func highlightRepository(
        prefs: NebulaPreferences = preferences
    ) -> any MarklyHighlightRepository {
        MarklyPreferencesRepository<MarklyHighlight>(prefs: prefs, key: "markly.highlights")
    }
}