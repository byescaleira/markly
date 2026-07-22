//
//  MarklyV03DomainTests.swift
//  Markly
//
//  Pure-logic tests for the v0.3 domain additions: highlight color set, highlight entity + repo
//  scoping, chapter derivation (H1 grouping + leading implicit + nested-block index map), paper
//  style ↔ theme round-trip, font-size stepping, and the v0.2→v0.3 settings Codable migration.
//  No I/O, no SwiftUI rendering — runs anywhere.
//

import XCTest
import Nebula
import SwiftUI
@testable import Markly

@MainActor
final class MarklyV03DomainTests: XCTestCase {

    private func parse(_ source: String) -> [MarklyBlock] {
        MarklyDocumentParser.parse(source)
    }

    // MARK: Highlight color

    func testHighlightColorRawValuesAndMarkerOrder() {
        XCTAssertEqual(MarklyHighlightColor.underline.rawValue, 0)
        XCTAssertEqual(MarklyHighlightColor.green.rawValue, 1)
        XCTAssertEqual(MarklyHighlightColor.blue.rawValue, 2)
        XCTAssertEqual(MarklyHighlightColor.yellow.rawValue, 3)
        XCTAssertEqual(MarklyHighlightColor.pink.rawValue, 4)
        XCTAssertEqual(MarklyHighlightColor.purple.rawValue, 5)
        XCTAssertEqual(MarklyHighlightColor.markerColors, [.yellow, .green, .blue, .pink, .purple])
        XCTAssertTrue(MarklyHighlightColor.underline.isUnderline)
        XCTAssertFalse(MarklyHighlightColor.yellow.isUnderline)
    }

    func testHighlightColorRoundTripsCodable() throws {
        for color in MarklyHighlightColor.allCases {
            let encoded = try JSONEncoder().encode(color)
            let decoded = try JSONDecoder().decode(MarklyHighlightColor.self, from: encoded)
            XCTAssertEqual(decoded, color)
        }
    }

    func testHighlightEntityIsCodableAndIdentifiable() throws {
        let highlight = MarklyHighlight(
            bookID: UUID(), sectionID: MarklySectionID(raw: "h1-x"), range: 3..<8, color: .green, note: "note"
        )
        let data = try JSONEncoder().encode([highlight])
        let decoded = try JSONDecoder().decode([MarklyHighlight].self, from: data)
        XCTAssertEqual(decoded, [highlight])
        XCTAssertEqual(decoded.first?.range, 3..<8)
        XCTAssertEqual(decoded.first?.note, "note")
    }

    // MARK: Chapters

    func testChaptersGroupByH1() {
        let blocks = parse("# Chapter One\n\ntext one\n\n## Sub\n\nsub text\n\n# Chapter Two\n\ntext two")
        let chapters = MarklyChapters.entries(from: blocks)
        XCTAssertEqual(chapters.count, 2)
        XCTAssertEqual(chapters[0].title, "Chapter One")
        XCTAssertEqual(chapters[1].title, "Chapter Two")
        XCTAssertFalse(chapters[0].isImplicit)
        // Chapter One spans its H1, the paragraph, the ## subheading, and the sub paragraph.
        XCTAssertGreaterThan(chapters[0].blockIDs.count, 3)
        XCTAssertEqual(chapters[1].blockIDs.count, 2, "Chapter Two is its H1 + one paragraph")
    }

    func testLeadingBlocksFormImplicitChapter() {
        let blocks = parse("Intro before any heading\n\n# Chapter One\n\ntext")
        let chapters = MarklyChapters.entries(from: blocks)
        XCTAssertEqual(chapters.count, 2)
        XCTAssertTrue(chapters[0].isImplicit)
        XCTAssertEqual(chapters[0].title, MarklyChapters.startOfDocumentTitle)
        XCTAssertEqual(chapters[0].blockIDs.count, 1)
        XCTAssertEqual(chapters[1].title, "Chapter One")
    }

    func testNoH1ProducesSingleImplicitChapter() {
        let blocks = parse("Intro\n\n## A subheading\n\nmore text")
        let chapters = MarklyChapters.entries(from: blocks)
        XCTAssertEqual(chapters.count, 1)
        XCTAssertTrue(chapters[0].isImplicit)
        XCTAssertEqual(chapters[0].title, MarklyChapters.startOfDocumentTitle)
        // The whole document is one chapter.
        XCTAssertEqual(chapters[0].blockIDs.count, blocks.count)
    }

    func testEmptyBlocksProduceNoChapters() {
        XCTAssertTrue(MarklyChapters.entries(from: []).isEmpty)
        XCTAssertTrue(MarklyChapters.indexMap(from: []).isEmpty)
    }

    func testIndexMapAssignsNestedBlocksToEnclosingChapter() {
        // A block quote inside Chapter Two must map to chapter index 1, not split on any nested
        // heading, and nested blocks inherit the enclosing top-level chapter.
        // Blocks: [0]intro para, [1]# One, [2]text para, [3]# Two, [4]> quote.
        let blocks = parse("intro\n\n# Chapter One\n\ntext\n\n# Chapter Two\n\n> a nested quote")
        let chapters = MarklyChapters.entries(from: blocks)
        let map = MarklyChapters.indexMap(from: blocks)
        XCTAssertEqual(chapters.count, 3, "implicit leading + two H1 chapters")

        // Leading intro → chapter 0 (implicit).
        XCTAssertEqual(map[blocks[0].id], 0)
        // Chapter One H1 → chapter 1.
        XCTAssertEqual(map[blocks[1].id], 1)
        // Chapter Two H1 → chapter 2.
        XCTAssertEqual(map[blocks[3].id], 2)
        // The nested block-quote paragraph → chapter 2 (enclosing Chapter Two).
        if case let .blockQuote(inner, _) = blocks[4] {
            XCTAssertEqual(map[inner[0].id], 2, "nested blocks inherit the enclosing chapter")
        } else {
            XCTFail("expected a block quote")
        }
    }

    func testIndexMapAgreesWithEntriesBlockIDs() {
        let blocks = parse("# A\n\ntext\n\n## sub\n\n- list item\n\n# B\n\n> quote")
        let chapters = MarklyChapters.entries(from: blocks)
        let map = MarklyChapters.indexMap(from: blocks)
        for (index, chapter) in chapters.enumerated() {
            for id in chapter.blockIDs {
                XCTAssertEqual(map[id], index, "chapter \(index) block id should map to its own index")
            }
        }
    }

    func testChapterFirstBlockIDIsScrollTarget() {
        let blocks = parse("# Chapter One\n\ntext\n\n# Chapter Two\n\ntext two")
        let chapters = MarklyChapters.entries(from: blocks)
        let h1One = blocks[0]
        let h1Two = blocks[2]
        XCTAssertEqual(chapters[0].firstBlockID, h1One.id)
        XCTAssertEqual(chapters[1].firstBlockID, h1Two.id)
    }

    // MARK: Paper style + font size

    func testPaperStyleFromThemeRoundTripsConcreteThemes() {
        XCTAssertEqual(PaperStyle.from(theme: .light), .white)
        XCTAssertEqual(PaperStyle.from(theme: .dark), .dark)
        XCTAssertEqual(PaperStyle.from(theme: .sepia), .sepia)
        XCTAssertEqual(PaperStyle.from(theme: .night), .night)
    }

    func testPaperStyleAutoResolvesFromColorScheme() {
        XCTAssertEqual(PaperStyle.auto.resolvedTheme(colorScheme: .dark), .dark)
        XCTAssertEqual(PaperStyle.auto.resolvedTheme(colorScheme: .light), .light)
        XCTAssertEqual(PaperStyle.sepia.resolvedTheme(colorScheme: .dark), .sepia)
        XCTAssertEqual(PaperStyle.night.resolvedTheme(colorScheme: .light), .night)
    }

    func testFontSizeDefaultAndStepping() {
        XCTAssertEqual(MarklyFontSize.default, .large)
        XCTAssertEqual(MarklyFontSize.large.nextLarger, .extraLarge)
        XCTAssertEqual(MarklyFontSize.large.nextSmaller, .medium)
        XCTAssertNil(MarklyFontSize.allCases.last!.nextLarger)
        XCTAssertNil(MarklyFontSize.allCases.first!.nextSmaller)
    }

    // MARK: Settings migration

    func testSettingsDecodeLegacyV02ThemeIntoPaperStyle() throws {
        // A v0.2 store persisted only `theme` + `readingMode`.
        let legacyJSON = """
        {"theme":"sepia","readingMode":"paged"}
        """.data(using: .utf8)!
        let settings = try JSONDecoder().decode(MarklyReaderSettings.self, from: legacyJSON)
        XCTAssertEqual(settings.paperStyle, .sepia, "legacy theme should migrate to paperStyle")
        XCTAssertEqual(settings.readingMode, .paged)
        XCTAssertEqual(settings.fontSize, .default, "absent fields should fall back to defaults")
        XCTAssertEqual(settings.brightness, 1.0)
        XCTAssertEqual(settings.lastHighlightColor, .yellow)
    }

    func testSettingsRoundTripsAllV03Fields() throws {
        let settings = MarklyReaderSettings(
            readingMode: .paged, paperStyle: .night, fontSize: .accessibilityLarge,
            brightness: 0.3, lastHighlightColor: .purple
        )
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(MarklyReaderSettings.self, from: data)
        XCTAssertEqual(decoded, settings)
    }

    // MARK: Highlight repository scoping

    func testHighlightsAreScopedToCurrentBook() async throws {
        let bookA = MarklyLiteralBook(title: "A", markdown: "# A")
        let bookB = MarklyLiteralBook(title: "B", markdown: "# B")
        let repo = NebulaFakeRepository<MarklyHighlight>()

        try await repo.save(
            MarklyHighlight(bookID: bookA.id, sectionID: MarklySectionID(raw: "h1-a"), range: 0..<3, color: .yellow)
        )

        let controllerB = MarklyReaderController(book: bookB, highlightRepository: repo)
        await controllerB.refreshHighlights()
        XCTAssertTrue(controllerB.highlights.isEmpty, "highlights must be scoped to the current book")
    }

    func testControllerAddHighlightPersistsAndUsesStickyColor() async throws {
        let book = MarklyLiteralBook(title: "A", markdown: "# A")
        let repo = NebulaFakeRepository<MarklyHighlight>()
        let controller = MarklyReaderController(book: book, highlightRepository: repo)
        controller.setLastHighlightColor(.blue)

        let created = await controller.addHighlight(at: MarklySectionID(raw: "h1-a"), range: 2..<5)
        XCTAssertEqual(created.color, .blue)
        XCTAssertEqual(controller.highlights.count, 1)
        XCTAssertEqual(controller.highlights.first?.color, .blue)
        XCTAssertEqual(controller.highlights.first?.range, 2..<5)

        // Changing color of an existing highlight updates the sticky color.
        await controller.setHighlightColor(.pink, for: created.id)
        XCTAssertEqual(controller.highlights.first?.color, .pink)
        XCTAssertEqual(controller.lastHighlightColor, .pink)
    }

    /// Regression for the "note on a fresh selection" flow (Apple Books lets a user attach a note to
    /// a new selection without applying a color first): the toolbar creates a highlight via
    /// `addHighlight` (sticky color) and then attaches the note via `setHighlightNote`. The two-step
    /// sequence must land a single highlight carrying the note.
    func testCreateThenSetNoteProducesSingleHighlightWithNote() async throws {
        let book = MarklyLiteralBook(title: "A", markdown: "# A")
        let repo = NebulaFakeRepository<MarklyHighlight>()
        let controller = MarklyReaderController(book: book, highlightRepository: repo)
        controller.setLastHighlightColor(.green)

        let created = await controller.addHighlight(at: MarklySectionID(raw: "h1-a"), range: 0..<4)
        await controller.setHighlightNote("my note", for: created.id)

        XCTAssertEqual(controller.highlights.count, 1, "create-then-note must not duplicate the highlight")
        XCTAssertEqual(controller.highlights.first?.note, "my note")
        XCTAssertEqual(controller.highlights.first?.color, .green)
        XCTAssertEqual(controller.highlights.first?.range, 0..<4)
    }

    /// An empty note on a fresh selection is a no-op at the note layer (the toolbar avoids creating
    /// an empty highlight); setting a note to `nil` clears an existing one.
    func testSetNoteNilClearsExistingNote() async throws {
        let book = MarklyLiteralBook(title: "A", markdown: "# A")
        let repo = NebulaFakeRepository<MarklyHighlight>()
        let controller = MarklyReaderController(book: book, highlightRepository: repo)

        let created = await controller.addHighlight(at: MarklySectionID(raw: "h1-a"), range: 0..<4)
        await controller.setHighlightNote("temp", for: created.id)
        XCTAssertEqual(controller.highlights.first?.note, "temp")
        await controller.setHighlightNote(nil, for: created.id)
        XCTAssertNil(controller.highlights.first?.note)
    }
}