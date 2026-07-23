//
//  MarklyV03DomainTests.swift
//  Markly
//
//  Pure-logic tests for the v0.3 domain additions: highlight color set, highlight entity + repo
//  scoping, chapter derivation (H1 grouping + leading implicit + nested-block index map), paper
//  style ↔ theme round-trip, font-size stepping, and the v0.2→v0.3 settings Codable migration.
//  No I/O, no SwiftUI rendering — runs anywhere.
//

import Testing
import Foundation
import Nebula
import SwiftUI
@testable import Markly

@MainActor
@Suite struct MarklyV03DomainTests {

    private func parse(_ source: String) -> [MarklyBlock] {
        MarklyDocumentParser.parse(source)
    }

    // MARK: Highlight color

    @Test func highlightColorRawValuesAndMarkerOrder() {
        #expect(MarklyHighlightColor.underline.rawValue == 0)
        #expect(MarklyHighlightColor.green.rawValue == 1)
        #expect(MarklyHighlightColor.blue.rawValue == 2)
        #expect(MarklyHighlightColor.yellow.rawValue == 3)
        #expect(MarklyHighlightColor.pink.rawValue == 4)
        #expect(MarklyHighlightColor.purple.rawValue == 5)
        #expect(MarklyHighlightColor.markerColors == [.yellow, .green, .blue, .pink, .purple])
        #expect(MarklyHighlightColor.underline.isUnderline)
        #expect(!MarklyHighlightColor.yellow.isUnderline)
    }

    @Test func highlightColorRoundTripsCodable() throws {
        for color in MarklyHighlightColor.allCases {
            let encoded = try JSONEncoder().encode(color)
            let decoded = try JSONDecoder().decode(MarklyHighlightColor.self, from: encoded)
            #expect(decoded == color)
        }
    }

    @Test func highlightEntityIsCodableAndIdentifiable() throws {
        let highlight = MarklyHighlight(
            bookID: UUID(), sectionID: MarklySectionID(raw: "h1-x"), range: 3..<8, color: .green, note: "note"
        )
        let data = try JSONEncoder().encode([highlight])
        let decoded = try JSONDecoder().decode([MarklyHighlight].self, from: data)
        #expect(decoded == [highlight])
        #expect(decoded.first?.range == 3..<8)
        #expect(decoded.first?.note == "note")
    }

    // MARK: Chapters

    @Test func chaptersGroupByH1() {
        let blocks = parse("# Chapter One\n\ntext one\n\n## Sub\n\nsub text\n\n# Chapter Two\n\ntext two")
        let chapters = MarklyChapters.entries(from: blocks)
        #expect(chapters.count == 2)
        #expect(chapters[0].title == "Chapter One")
        #expect(chapters[1].title == "Chapter Two")
        #expect(!chapters[0].isImplicit)
        // Chapter One spans its H1, the paragraph, the ## subheading, and the sub paragraph.
        #expect(chapters[0].blockIDs.count > 3)
        #expect(chapters[1].blockIDs.count == 2, "Chapter Two is its H1 + one paragraph")
    }

    @Test func leadingBlocksFormImplicitChapter() {
        let blocks = parse("Intro before any heading\n\n# Chapter One\n\ntext")
        let chapters = MarklyChapters.entries(from: blocks)
        #expect(chapters.count == 2)
        #expect(chapters[0].isImplicit)
        #expect(chapters[0].title == MarklyChapters.startOfDocumentTitle)
        #expect(chapters[0].blockIDs.count == 1)
        #expect(chapters[1].title == "Chapter One")
    }

    @Test func noH1ProducesSingleImplicitChapter() {
        let blocks = parse("Intro\n\n## A subheading\n\nmore text")
        let chapters = MarklyChapters.entries(from: blocks)
        #expect(chapters.count == 1)
        #expect(chapters[0].isImplicit)
        #expect(chapters[0].title == MarklyChapters.startOfDocumentTitle)
        // The whole document is one chapter.
        #expect(chapters[0].blockIDs.count == blocks.count)
    }

    @Test func emptyBlocksProduceNoChapters() {
        #expect(MarklyChapters.entries(from: []).isEmpty)
        #expect(MarklyChapters.indexMap(from: []).isEmpty)
    }

    @Test func indexMapAssignsNestedBlocksToEnclosingChapter() {
        // A block quote inside Chapter Two must map to chapter index 1, not split on any nested
        // heading, and nested blocks inherit the enclosing top-level chapter.
        // Blocks: [0]intro para, [1]# One, [2]text para, [3]# Two, [4]> quote.
        let blocks = parse("intro\n\n# Chapter One\n\ntext\n\n# Chapter Two\n\n> a nested quote")
        let chapters = MarklyChapters.entries(from: blocks)
        let map = MarklyChapters.indexMap(from: blocks)
        #expect(chapters.count == 3, "implicit leading + two H1 chapters")

        // Leading intro → chapter 0 (implicit).
        #expect(map[blocks[0].id] == 0)
        // Chapter One H1 → chapter 1.
        #expect(map[blocks[1].id] == 1)
        // Chapter Two H1 → chapter 2.
        #expect(map[blocks[3].id] == 2)
        // The nested block-quote paragraph → chapter 2 (enclosing Chapter Two).
        if case let .blockQuote(inner, _) = blocks[4] {
            #expect(map[inner[0].id] == 2, "nested blocks inherit the enclosing chapter")
        } else {
            Issue.record("expected a block quote")
        }
    }

    @Test func indexMapAgreesWithEntriesBlockIDs() {
        let blocks = parse("# A\n\ntext\n\n## sub\n\n- list item\n\n# B\n\n> quote")
        let chapters = MarklyChapters.entries(from: blocks)
        let map = MarklyChapters.indexMap(from: blocks)
        for (index, chapter) in chapters.enumerated() {
            for id in chapter.blockIDs {
                #expect(map[id] == index, "chapter \(index) block id should map to its own index")
            }
        }
    }

    @Test func chapterFirstBlockIDIsScrollTarget() {
        let blocks = parse("# Chapter One\n\ntext\n\n# Chapter Two\n\ntext two")
        let chapters = MarklyChapters.entries(from: blocks)
        let h1One = blocks[0]
        let h1Two = blocks[2]
        #expect(chapters[0].firstBlockID == h1One.id)
        #expect(chapters[1].firstBlockID == h1Two.id)
    }

    // MARK: Paper style + font size

    @Test func paperStyleFromThemeRoundTripsConcreteThemes() {
        #expect(PaperStyle.from(theme: .light) == .white)
        #expect(PaperStyle.from(theme: .dark) == .dark)
        #expect(PaperStyle.from(theme: .sepia) == .sepia)
        #expect(PaperStyle.from(theme: .night) == .night)
    }

    @Test func paperStyleAutoResolvesFromColorScheme() {
        #expect(PaperStyle.auto.resolvedTheme(colorScheme: .dark) == .dark)
        #expect(PaperStyle.auto.resolvedTheme(colorScheme: .light) == .light)
        #expect(PaperStyle.sepia.resolvedTheme(colorScheme: .dark) == .sepia)
        #expect(PaperStyle.night.resolvedTheme(colorScheme: .light) == .night)
    }

    @Test func fontSizeDefaultAndStepping() {
        #expect(MarklyFontSize.default == .large)
        #expect(MarklyFontSize.large.nextLarger == .extraLarge)
        #expect(MarklyFontSize.large.nextSmaller == .medium)
        #expect(MarklyFontSize.allCases.last!.nextLarger == nil)
        #expect(MarklyFontSize.allCases.first!.nextSmaller == nil)
    }

    // MARK: Settings migration

    @Test func settingsDecodeLegacyV02ThemeIntoPaperStyle() throws {
        // A v0.2 store persisted only `theme` + `readingMode`.
        let legacyJSON = """
        {"theme":"sepia","readingMode":"paged"}
        """.data(using: .utf8)!
        let settings = try JSONDecoder().decode(MarklyReaderSettings.self, from: legacyJSON)
        #expect(settings.paperStyle == .sepia, "legacy theme should migrate to paperStyle")
        #expect(settings.readingMode == .paged)
        #expect(settings.fontSize == .default, "absent fields should fall back to defaults")
        #expect(settings.brightness == 1.0)
        #expect(settings.lastHighlightColor == .yellow)
    }

    @Test func settingsRoundTripsAllV03Fields() throws {
        let settings = MarklyReaderSettings(
            readingMode: .paged, paperStyle: .night, fontSize: .accessibilityLarge,
            brightness: 0.3, lastHighlightColor: .purple
        )
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(MarklyReaderSettings.self, from: data)
        #expect(decoded == settings)
    }

    // MARK: Highlight repository scoping

    @Test func highlightsAreScopedToCurrentBook() async throws {
        let bookA = MarklyLiteralBook(title: "A", markdown: "# A")
        let bookB = MarklyLiteralBook(title: "B", markdown: "# B")
        let repo = NebulaFakeRepository<MarklyHighlight>()

        try await repo.save(
            MarklyHighlight(bookID: bookA.id, sectionID: MarklySectionID(raw: "h1-a"), range: 0..<3, color: .yellow)
        )

        let controllerB = MarklyReaderController(book: bookB, highlightRepository: repo)
        await controllerB.refreshHighlights()
        #expect(controllerB.highlights.isEmpty, "highlights must be scoped to the current book")
    }

    @Test func controllerAddHighlightPersistsAndUsesStickyColor() async throws {
        let book = MarklyLiteralBook(title: "A", markdown: "# A")
        let repo = NebulaFakeRepository<MarklyHighlight>()
        let controller = MarklyReaderController(book: book, highlightRepository: repo)
        controller.setLastHighlightColor(.blue)

        let created = await controller.addHighlight(at: MarklySectionID(raw: "h1-a"), range: 2..<5)
        #expect(created.color == .blue)
        #expect(controller.highlights.count == 1)
        #expect(controller.highlights.first?.color == .blue)
        #expect(controller.highlights.first?.range == 2..<5)

        // Changing color of an existing highlight updates the sticky color.
        await controller.setHighlightColor(.pink, for: created.id)
        #expect(controller.highlights.first?.color == .pink)
        #expect(controller.lastHighlightColor == .pink)
    }

    /// Regression for the "note on a fresh selection" flow (Apple Books lets a user attach a note to
    /// a new selection without applying a color first): the toolbar creates a highlight via
    /// `addHighlight` (sticky color) and then attaches the note via `setHighlightNote`. The two-step
    /// sequence must land a single highlight carrying the note.
    @Test func createThenSetNoteProducesSingleHighlightWithNote() async throws {
        let book = MarklyLiteralBook(title: "A", markdown: "# A")
        let repo = NebulaFakeRepository<MarklyHighlight>()
        let controller = MarklyReaderController(book: book, highlightRepository: repo)
        controller.setLastHighlightColor(.green)

        let created = await controller.addHighlight(at: MarklySectionID(raw: "h1-a"), range: 0..<4)
        await controller.setHighlightNote("my note", for: created.id)

        #expect(controller.highlights.count == 1, "create-then-note must not duplicate the highlight")
        #expect(controller.highlights.first?.note == "my note")
        #expect(controller.highlights.first?.color == .green)
        #expect(controller.highlights.first?.range == 0..<4)
    }

    /// An empty note on a fresh selection is a no-op at the note layer (the toolbar avoids creating
    /// an empty highlight); setting a note to `nil` clears an existing one.
    @Test func setNoteNilClearsExistingNote() async throws {
        let book = MarklyLiteralBook(title: "A", markdown: "# A")
        let repo = NebulaFakeRepository<MarklyHighlight>()
        let controller = MarklyReaderController(book: book, highlightRepository: repo)

        let created = await controller.addHighlight(at: MarklySectionID(raw: "h1-a"), range: 0..<4)
        await controller.setHighlightNote("temp", for: created.id)
        #expect(controller.highlights.first?.note == "temp")
        await controller.setHighlightNote(nil, for: created.id)
        #expect(controller.highlights.first?.note == nil)
    }

    // MARK: Chapter navigation

    @Test func chapterNavigationAdvancesRetreatsAndStopsAtEdges() async {
        let md = "# One\n\ntext\n\n# Two\n\ntext\n\n# Three\n\ntext"
        let book = MarklyLiteralBook(title: "Book", markdown: md)
        let suite = UserDefaults(suiteName: "markly.tests.\(UUID().uuidString)")!
        let settingsStore = MarklyReaderSettingsStore(prefs: NebulaDefaults(suite), key: "test.chapter-nav")
        let controller = MarklyReaderController(book: book, settingsStore: settingsStore)
        let blocks = parse(md)
        let chapters = MarklyChapters.entries(from: blocks)
        let map = MarklyChapters.indexMap(from: blocks)
        controller.setChapters(chapters, sectionMap: map)

        // No current section -> no current chapter; next/prev are no-ops (no scroll request).
        #expect(controller.currentChapter == nil)
        let beforeAny = controller.scrollRequest
        controller.goToNextChapter()
        #expect(controller.scrollRequest == beforeAny)
        controller.goToPreviousChapter()
        #expect(controller.scrollRequest == beforeAny)

        // Land on Chapter One.
        controller.currentSectionID = chapters[0].firstBlockID
        #expect(controller.currentChapter?.title == "One")

        // Next -> Chapter Two's first block.
        controller.goToNextChapter()
        #expect(controller.scrollRequest?.id == chapters[1].firstBlockID)

        // Arrive at Chapter Two; next -> Chapter Three.
        controller.currentSectionID = chapters[1].firstBlockID
        controller.goToNextChapter()
        #expect(controller.scrollRequest?.id == chapters[2].firstBlockID)

        // At the last chapter, next is a no-op (scroll request unchanged).
        controller.currentSectionID = chapters[2].firstBlockID
        let atLast = controller.scrollRequest
        controller.goToNextChapter()
        #expect(controller.scrollRequest == atLast)

        // From Chapter Two, previous -> Chapter One.
        controller.currentSectionID = chapters[1].firstBlockID
        controller.goToPreviousChapter()
        #expect(controller.scrollRequest?.id == chapters[0].firstBlockID)

        // Out-of-range index is a no-op; a valid index scrolls to that chapter's first block.
        let beforeOob = controller.scrollRequest
        controller.goToChapter(at: 99)
        #expect(controller.scrollRequest == beforeOob)
        controller.goToChapter(at: 2)
        #expect(controller.scrollRequest?.id == chapters[2].firstBlockID)
    }

    // MARK: Settings decode fallback/priority

    @Test func settingsDecodePaperStylePriorityOverLegacyTheme() throws {
        // Both keys present -> explicit paperStyle wins over the legacy theme.
        let json = #"{"paperStyle":"night","theme":"sepia","readingMode":"continuous"}"#.data(using: .utf8)!
        let settings = try JSONDecoder().decode(MarklyReaderSettings.self, from: json)
        #expect(settings.paperStyle == .night, "explicit paperStyle wins over legacy theme")
        #expect(settings.readingMode == .continuous)
    }

    @Test func settingsDecodeAbsentFieldsFallBackToDefaults() throws {
        let json = #"{"paperStyle":"white"}"#.data(using: .utf8)!
        let settings = try JSONDecoder().decode(MarklyReaderSettings.self, from: json)
        #expect(settings.paperStyle == .white)
        #expect(settings.readingMode == .continuous)
        #expect(settings.fontSize == .large)
        #expect(settings.brightness == 1.0)
        #expect(settings.lastHighlightColor == .yellow)
    }

    @Test func settingsDecodeFallsBackToAutoWhenNoPaperOrTheme() throws {
        let json = #"{"readingMode":"paged"}"#.data(using: .utf8)!
        let settings = try JSONDecoder().decode(MarklyReaderSettings.self, from: json)
        #expect(settings.paperStyle == .auto)
        #expect(settings.readingMode == .paged)
    }

    // MARK: Controller theme resolution

    @Test func controllerResolvesThemeFromColorSchemeAndPersists() {
        let suite = UserDefaults(suiteName: "markly.tests.\(UUID().uuidString)")!
        let settingsStore = MarklyReaderSettingsStore(prefs: NebulaDefaults(suite), key: "test.theme-resolve")
        let controller = MarklyReaderController(book: MarklyLiteralBook(title: "T", markdown: "# A"), settingsStore: settingsStore)

        // Fresh store -> seeded default (.auto).
        #expect(controller.configuration.paperStyle == .auto)

        // .auto follows the system color scheme.
        controller.resolveAndUpdateTheme(colorScheme: .dark)
        #expect(controller.configuration.theme == .dark)
        controller.resolveAndUpdateTheme(colorScheme: .light)
        #expect(controller.configuration.theme == .light)

        // A concrete paper style ignores the color scheme.
        controller.setPaperStyle(.night)
        controller.resolveAndUpdateTheme(colorScheme: .light)
        #expect(controller.configuration.theme == .night)

        // setPaperStyle persists to the store.
        #expect(settingsStore.load()?.paperStyle == .night)
    }
}