//
//  MarklyReadingTests.swift
//  Markly
//
//  Verifies Phase 2 Track 1: TOC derivation, the NebulaPreferences-backed repository, and the
//  controller's bookmark/reading-position logic. Uses Nebula's in-memory fake repositories so no
//  UserDefaults I/O is required.
//

import Testing
import Foundation
@testable import Markly
import Nebula

@MainActor
@Suite struct MarklyReadingTests {

    // MARK: - TOC derivation

    @Test func tocExtractsHeadingsInOrder() {
        let blocks = MarklyDocumentParser.parse("# One\n\ntext\n\n## Two\n\n> ## Nested in quote")
        let entries = MarklyTOC.entries(from: blocks)
        #expect(entries.map(\.title) == ["One", "Two", "Nested in quote"])
        #expect(entries.map(\.level) == [1, 2, 2])
    }

    @Test func tocEntriesMatchBlockSectionIDs() {
        let blocks = MarklyDocumentParser.parse("# Heading One")
        let entries = MarklyTOC.entries(from: blocks)
        #expect(entries.first?.id.raw == blocks.first?.id.raw)
    }

    // MARK: - Preferences-backed repository

    @Test func preferencesRepositorySavesAndFinds() async throws {
        let suite = UserDefaults(suiteName: "markly.tests.\(UUID().uuidString)")!
        let prefs = NebulaDefaults(suite)
        let repo = MarklyPreferencesRepository<MarklyBookmark>(prefs: prefs, key: "test.bookmarks")

        let bookmark = MarklyBookmark(bookID: UUID(), sectionID: MarklySectionID(raw: "h1-x"), title: "First")
        try await repo.save(bookmark)
        let found = try await repo.find(id: bookmark.id)
        #expect(found?.title == "First")

        try await repo.delete(bookmark.id)
        let after = try await repo.find(id: bookmark.id)
        #expect(after == nil)
    }

    @Test func preferencesRepositoryUpsertsById() async throws {
        let suite = UserDefaults(suiteName: "markly.tests.\(UUID().uuidString)")!
        let prefs = NebulaDefaults(suite)
        let repo = MarklyPreferencesRepository<MarklyReadingPosition>(prefs: prefs, key: "test.positions")

        let id = UUID()
        try await repo.save(MarklyReadingPosition(id: id, sectionID: MarklySectionID(raw: "h1-a")))
        try await repo.save(MarklyReadingPosition(id: id, sectionID: MarklySectionID(raw: "h1-b")))
        let count = try await repo.count()
        #expect(count == 1, "Saving the same id should upsert, not append")
        let found = try await repo.find(id: id)
        #expect(found?.sectionID.raw == "h1-b")
    }

    // MARK: - Controller bookmarks + position

    @Test func controllerAddRemoveBookmark() async {
        let book = MarklyLiteralBook(title: "T", markdown: "# A")
        let controller = MarklyReaderController(
            book: book,
            positionRepository: NebulaFakeRepository<MarklyReadingPosition>(),
            bookmarkRepository: NebulaFakeRepository<MarklyBookmark>()
        )

        let section = MarklySectionID(raw: "h1-a")
        #expect(!controller.isBookmarked(section))
        await controller.addBookmark(at: section, title: "A")
        #expect(controller.isBookmarked(section))
        #expect(controller.bookmarks.count == 1)

        if let id = controller.bookmarks.first(where: { $0.sectionID == section })?.id {
            await controller.removeBookmark(id)
        }
        #expect(!controller.isBookmarked(section))
        #expect(controller.bookmarks.isEmpty)
    }

    @Test func controllerPositionSaveAndRestore() async {
        let book = MarklyLiteralBook(title: "T", markdown: "# A\n\n# B")
        let posRepo = NebulaFakeRepository<MarklyReadingPosition>()
        let controller = MarklyReaderController(
            book: book,
            positionRepository: posRepo,
            bookmarkRepository: NebulaFakeRepository<MarklyBookmark>()
        )

        // No position saved yet → restore returns nil.
        let initial = await controller.restorePosition()
        #expect(initial == nil)

        // Setting the current section and saving persists it keyed by the book id.
        controller.currentSectionID = MarklySectionID(raw: "h1-b")
        await controller.saveCurrentPosition()
        let restored = await controller.restorePosition()
        #expect(restored?.raw == "h1-b")

        // The saved position is keyed by book.id (one per book).
        let stored = try? await posRepo.find(id: book.id)
        #expect(stored?.sectionID.raw == "h1-b")
    }

    // MARK: - Reader settings (Track 2)

    @Test func settingsStoreRoundTripsAndPersistsAcrossInstances() {
        let suite = UserDefaults(suiteName: "markly.tests.\(UUID().uuidString)")!
        let prefs = NebulaDefaults(suite)
        let key = "test.reader.settings"

        let store1 = MarklyReaderSettingsStore(prefs: prefs, key: key)
        #expect(store1.load() == nil, "Nothing stored yet")

        store1.save(MarklyReaderSettings(readingMode: .paged, paperStyle: .sepia))

        // A fresh store reading the same key sees the saved value.
        let store2 = MarklyReaderSettingsStore(prefs: prefs, key: key)
        let loaded = store2.load()
        #expect(loaded?.paperStyle == .sepia)
        #expect(loaded?.readingMode == .paged)
    }

    @Test func controllerRestoresPersistedSettingsOverridingSeededConfiguration() {
        let suite = UserDefaults(suiteName: "markly.tests.\(UUID().uuidString)")!
        let prefs = NebulaDefaults(suite)
        let settingsStore = MarklyReaderSettingsStore(prefs: prefs, key: "test.reader.settings")
        settingsStore.save(MarklyReaderSettings(readingMode: .paged, paperStyle: .night, fontSize: .extraLarge, brightness: 0.5))

        let controller = MarklyReaderController(
            book: MarklyLiteralBook(title: "T", markdown: "# A"),
            configuration: MarklyConfiguration(theme: .light, readingMode: .continuous),
            settingsStore: settingsStore
        )

        #expect(controller.configuration.paperStyle == .night, "Persisted paper style should override seeded config")
        #expect(controller.configuration.readingMode == .paged, "Persisted mode should override seeded config")
        #expect(controller.configuration.fontSize == .extraLarge, "Persisted font size should override seeded config")
        #expect(controller.configuration.brightness == 0.5, "Persisted brightness should override seeded config")
    }

    @Test func controllerSetReadingModePersists() {
        let suite = UserDefaults(suiteName: "markly.tests.\(UUID().uuidString)")!
        let prefs = NebulaDefaults(suite)
        let settingsStore = MarklyReaderSettingsStore(prefs: prefs, key: "test.reader.settings")

        let controller = MarklyReaderController(
            book: MarklyLiteralBook(title: "T", markdown: "# A"),
            settingsStore: settingsStore
        )
        controller.setReadingMode(.paged)

        let loaded = settingsStore.load()
        #expect(loaded?.readingMode == .paged)
        #expect(controller.configuration.readingMode == .paged)
    }

    @Test func controllerBookmarksAreScopedToCurrentBook() async throws {
        let bookA = MarklyLiteralBook(title: "A", markdown: "# A")
        let bookB = MarklyLiteralBook(title: "B", markdown: "# B")
        let bmRepo = NebulaFakeRepository<MarklyBookmark>()

        // Seed a bookmark for bookA directly through the shared repo.
        try await bmRepo.save(MarklyBookmark(bookID: bookA.id, sectionID: MarklySectionID(raw: "h1-a"), title: "A1"))

        // bookB's controller should not see bookA's bookmark.
        let controllerB = MarklyReaderController(book: bookB, bookmarkRepository: bmRepo)
        await controllerB.refreshBookmarks()
        #expect(controllerB.bookmarks.isEmpty, "Bookmarks must be scoped to the current book")

        // bookA's controller should see it.
        let controllerA = MarklyReaderController(book: bookA, bookmarkRepository: bmRepo)
        await controllerA.refreshBookmarks()
        #expect(controllerA.bookmarks.count == 1)
    }
}