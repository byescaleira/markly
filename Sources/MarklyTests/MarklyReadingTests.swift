//
//  MarklyReadingTests.swift
//  Markly
//
//  Verifies Phase 2 Track 1: TOC derivation, the NebulaPreferences-backed repository, and the
//  controller's bookmark/reading-position logic. Uses Nebula's in-memory fake repositories so no
//  UserDefaults I/O is required.
//

import XCTest
@testable import Markly
import Nebula

@MainActor
final class MarklyReadingTests: XCTestCase {

    // MARK: - TOC derivation

    func testTOCExtractsHeadingsInOrder() {
        let blocks = MarklyDocumentParser.parse("# One\n\ntext\n\n## Two\n\n> ## Nested in quote")
        let entries = MarklyTOC.entries(from: blocks)
        XCTAssertEqual(entries.map(\.title), ["One", "Two", "Nested in quote"])
        XCTAssertEqual(entries.map(\.level), [1, 2, 2])
    }

    func testTOCEntriesMatchBlockSectionIDs() {
        let blocks = MarklyDocumentParser.parse("# Heading One")
        let entries = MarklyTOC.entries(from: blocks)
        XCTAssertEqual(entries.first?.id.raw, blocks.first?.id.raw)
    }

    // MARK: - Preferences-backed repository

    func testPreferencesRepositorySavesAndFinds() async throws {
        let suite = UserDefaults(suiteName: "markly.tests.\(UUID().uuidString)")!
        let prefs = NebulaDefaults(suite)
        let repo = MarklyPreferencesRepository<MarklyBookmark>(prefs: prefs, key: "test.bookmarks")

        let bookmark = MarklyBookmark(bookID: UUID(), sectionID: MarklySectionID(raw: "h1-x"), title: "First")
        try await repo.save(bookmark)
        let found = try await repo.find(id: bookmark.id)
        XCTAssertEqual(found?.title, "First")

        try await repo.delete(bookmark.id)
        let after = try await repo.find(id: bookmark.id)
        XCTAssertNil(after)
    }

    func testPreferencesRepositoryUpsertsById() async throws {
        let suite = UserDefaults(suiteName: "markly.tests.\(UUID().uuidString)")!
        let prefs = NebulaDefaults(suite)
        let repo = MarklyPreferencesRepository<MarklyReadingPosition>(prefs: prefs, key: "test.positions")

        let id = UUID()
        try await repo.save(MarklyReadingPosition(id: id, sectionID: MarklySectionID(raw: "h1-a")))
        try await repo.save(MarklyReadingPosition(id: id, sectionID: MarklySectionID(raw: "h1-b")))
        let count = try await repo.count()
        XCTAssertEqual(count, 1, "Saving the same id should upsert, not append")
        let found = try await repo.find(id: id)
        XCTAssertEqual(found?.sectionID.raw, "h1-b")
    }

    // MARK: - Controller bookmarks + position

    func testControllerAddRemoveBookmark() async {
        let book = MarklyLiteralBook(title: "T", markdown: "# A")
        let controller = MarklyReaderController(
            book: book,
            positionRepository: NebulaFakeRepository<MarklyReadingPosition>(),
            bookmarkRepository: NebulaFakeRepository<MarklyBookmark>()
        )

        let section = MarklySectionID(raw: "h1-a")
        XCTAssertFalse(controller.isBookmarked(section))
        await controller.addBookmark(at: section, title: "A")
        XCTAssertTrue(controller.isBookmarked(section))
        XCTAssertEqual(controller.bookmarks.count, 1)

        if let id = controller.bookmarks.first(where: { $0.sectionID == section })?.id {
            await controller.removeBookmark(id)
        }
        XCTAssertFalse(controller.isBookmarked(section))
        XCTAssertTrue(controller.bookmarks.isEmpty)
    }

    func testControllerPositionSaveAndRestore() async {
        let book = MarklyLiteralBook(title: "T", markdown: "# A\n\n# B")
        let posRepo = NebulaFakeRepository<MarklyReadingPosition>()
        let controller = MarklyReaderController(
            book: book,
            positionRepository: posRepo,
            bookmarkRepository: NebulaFakeRepository<MarklyBookmark>()
        )

        // No position saved yet → restore returns nil.
        let initial = await controller.restorePosition()
        XCTAssertNil(initial)

        // Setting the current section and saving persists it keyed by the book id.
        controller.currentSectionID = MarklySectionID(raw: "h1-b")
        await controller.saveCurrentPosition()
        let restored = await controller.restorePosition()
        XCTAssertEqual(restored?.raw, "h1-b")

        // The saved position is keyed by book.id (one per book).
        let stored = try? await posRepo.find(id: book.id)
        XCTAssertEqual(stored?.sectionID.raw, "h1-b")
    }

    // MARK: - Reader settings (Track 2)

    func testSettingsStoreRoundTripsAndPersistsAcrossInstances() {
        let suite = UserDefaults(suiteName: "markly.tests.\(UUID().uuidString)")!
        let prefs = NebulaDefaults(suite)
        let key = "test.reader.settings"

        let store1 = MarklyReaderSettingsStore(prefs: prefs, key: key)
        XCTAssertNil(store1.load(), "Nothing stored yet")

        store1.save(MarklyReaderSettings(readingMode: .paged, paperStyle: .sepia))

        // A fresh store reading the same key sees the saved value.
        let store2 = MarklyReaderSettingsStore(prefs: prefs, key: key)
        let loaded = store2.load()
        XCTAssertEqual(loaded?.paperStyle, .sepia)
        XCTAssertEqual(loaded?.readingMode, .paged)
    }

    func testControllerRestoresPersistedSettingsOverridingSeededConfiguration() {
        let suite = UserDefaults(suiteName: "markly.tests.\(UUID().uuidString)")!
        let prefs = NebulaDefaults(suite)
        let settingsStore = MarklyReaderSettingsStore(prefs: prefs, key: "test.reader.settings")
        settingsStore.save(MarklyReaderSettings(readingMode: .paged, paperStyle: .night, fontSize: .extraLarge, brightness: 0.5))

        let controller = MarklyReaderController(
            book: MarklyLiteralBook(title: "T", markdown: "# A"),
            configuration: MarklyConfiguration(theme: .light, readingMode: .continuous),
            settingsStore: settingsStore
        )

        XCTAssertEqual(controller.configuration.paperStyle, .night, "Persisted paper style should override seeded config")
        XCTAssertEqual(controller.configuration.readingMode, .paged, "Persisted mode should override seeded config")
        XCTAssertEqual(controller.configuration.fontSize, .extraLarge, "Persisted font size should override seeded config")
        XCTAssertEqual(controller.configuration.brightness, 0.5, "Persisted brightness should override seeded config")
    }

    func testControllerSetReadingModePersists() {
        let suite = UserDefaults(suiteName: "markly.tests.\(UUID().uuidString)")!
        let prefs = NebulaDefaults(suite)
        let settingsStore = MarklyReaderSettingsStore(prefs: prefs, key: "test.reader.settings")

        let controller = MarklyReaderController(
            book: MarklyLiteralBook(title: "T", markdown: "# A"),
            settingsStore: settingsStore
        )
        controller.setReadingMode(.paged)

        let loaded = settingsStore.load()
        XCTAssertEqual(loaded?.readingMode, .paged)
        XCTAssertEqual(controller.configuration.readingMode, .paged)
    }

    func testControllerBookmarksAreScopedToCurrentBook() async throws {
        let bookA = MarklyLiteralBook(title: "A", markdown: "# A")
        let bookB = MarklyLiteralBook(title: "B", markdown: "# B")
        let bmRepo = NebulaFakeRepository<MarklyBookmark>()

        // Seed a bookmark for bookA directly through the shared repo.
        try await bmRepo.save(MarklyBookmark(bookID: bookA.id, sectionID: MarklySectionID(raw: "h1-a"), title: "A1"))

        // bookB's controller should not see bookA's bookmark.
        let controllerB = MarklyReaderController(book: bookB, bookmarkRepository: bmRepo)
        await controllerB.refreshBookmarks()
        XCTAssertTrue(controllerB.bookmarks.isEmpty, "Bookmarks must be scoped to the current book")

        // bookA's controller should see it.
        let controllerA = MarklyReaderController(book: bookA, bookmarkRepository: bmRepo)
        await controllerA.refreshBookmarks()
        XCTAssertEqual(controllerA.bookmarks.count, 1)
    }
}