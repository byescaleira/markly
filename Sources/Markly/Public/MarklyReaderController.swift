//
//  MarklyReaderController.swift
//  Markly
//
//  The host's programmatic handle on a reader: owns the live theme (via
//  `CosmosThemeObservable`), exposes the current section/chapter, drives scroll-to-section, and
//  manages reading-position persistence, bookmarks, highlights, and appearance settings over Nebula
//  repositories/preferences.
//
//  `@MainActor` + `@Observable` is the Swift-6-safe pattern Cosmos itself uses for
//  `CosmosThemeObservable`: the main actor serializes access and `@Observable` drives
//  view updates. Repository calls are `async throws` and hop off-main via `await`; state is
//  mutated back on the main actor. See docs/Architecture.md §4, §7.
//

import SwiftUI
import Cosmos
import Nebula

/// A programmatic handle on a `MarklyReader`, owned by the host.
@MainActor
@Observable
public final class MarklyReaderController {
    /// The book being read. Mutated by `MarklyReader` when the host swaps books (kept in sync with
    /// the view's `book` prop so `controller.book` never reports a stale title).
    public var book: any MarklyBook
    /// The reader configuration (mutable; the reader reads it live).
    public var configuration: MarklyConfiguration
    /// The live theme observable injected into the Cosmos environment.
    public let themeObservable: CosmosThemeObservable
    /// The section the reader is currently displaying (updated by the scroll surface).
    /// `internal(set)` so Markly's reader surface can mutate it while host apps only read it.
    public internal(set) var currentSectionID: MarklySectionID?

    /// The reading-position persistence seam (one position per book; keyed by `book.id`).
    public let positionRepository: any MarklyReadingPositionRepository
    /// The bookmark persistence seam.
    public let bookmarkRepository: any MarklyBookmarkRepository
    /// The highlight persistence seam.
    public let highlightRepository: any MarklyHighlightRepository
    /// The reader-settings persistence seam (paper style, font size, brightness, last highlight color).
    public let settingsStore: MarklyReaderSettingsStore
    /// The bookmarks for the current book (refreshed on load and on add/remove).
    public private(set) var bookmarks: [MarklyBookmark] = []
    /// The highlights for the current book (refreshed on load and on add/remove/update).
    public private(set) var highlights: [MarklyHighlight] = []
    /// The chapters derived from the book's top-level (`#`) headings (set on load).
    public private(set) var chapters: [MarklyChapter] = []
    /// A map from every block's section id (including nested blocks inside lists/block quotes) to
    /// its chapter index in `chapters`, so the current chapter can be resolved from the reader's
    /// `currentSectionID` even when that id belongs to a nested block. Set on load.
    public private(set) var sectionToChapter: [MarklySectionID: Int] = [:]
    /// The last-used highlight color (Apple Books' sticky-color behavior). Updated whenever a
    /// highlight is created or the user picks a color in the highlight toolbar; persisted in settings.
    public var lastHighlightColor: MarklyHighlightColor

    /// A pending scroll request emitted by `scrollTo(_:)` and consumed by the reading surface's
    /// `ScrollViewReader`. The `token` increments on every request so re-tapping the same TOC
    /// entry re-scrolls (a bare id would not, since the value would not change).
    public struct ScrollRequest: Sendable, Equatable {
        /// The section to scroll to.
        public let id: MarklySectionID
        /// A monotonic counter so identical requests still register as a change.
        public let token: Int
    }

    /// The current pending scroll request, or `nil` if none.
    public private(set) var scrollRequest: ScrollRequest?

    /// Creates a controller for a book. Repositories default to Markly's zero-config
    /// `NebulaPreferences`-backed stores; pass custom ones to back them with SwiftData/Core Data.
    /// Persisted reader settings (paper style, font size, brightness, reading mode) override the
    /// seeded `configuration` on launch so the user's last choice is restored; pass a no-op/
    /// in-memory `settingsStore` to disable that.
    public init(
        book: any MarklyBook,
        configuration: MarklyConfiguration = .default,
        positionRepository: any MarklyReadingPositionRepository = MarklyDefaultRepositories.readingPositionRepository(),
        bookmarkRepository: any MarklyBookmarkRepository = MarklyDefaultRepositories.bookmarkRepository(),
        highlightRepository: any MarklyHighlightRepository = MarklyDefaultRepositories.highlightRepository(),
        settingsStore: MarklyReaderSettingsStore = MarklyReaderSettingsStore()
    ) {
        self.book = book
        self.positionRepository = positionRepository
        self.bookmarkRepository = bookmarkRepository
        self.highlightRepository = highlightRepository
        self.settingsStore = settingsStore
        // Restore the user's last appearance/reading choices if present; otherwise keep the seeded
        // configuration.
        var config = configuration
        let saved = settingsStore.load()
        if let saved {
            config.readingMode = saved.readingMode
            config.paperStyle = saved.paperStyle
            config.fontSize = saved.fontSize
            config.brightness = saved.brightness
        }
        self.configuration = config
        self.lastHighlightColor = saved?.lastHighlightColor ?? .yellow
        self.themeObservable = CosmosThemeObservable(theme: config.paperStyle.fallbackTheme.cosmosTheme)
    }

    /// A snapshot of the current persisted settings.
    private func currentSettings() -> MarklyReaderSettings {
        MarklyReaderSettings(
            readingMode: configuration.readingMode,
            paperStyle: configuration.paperStyle,
            fontSize: configuration.fontSize,
            brightness: configuration.brightness,
            lastHighlightColor: lastHighlightColor
        )
    }

    // MARK: Appearance

    /// Resolves the active paper style to a concrete theme given the system color scheme and pushes
    /// it to the live theme observable. The reader calls this on appear and whenever the system
    /// appearance or the user's `paperStyle` changes (so `.auto` follows the system live).
    public func resolveAndUpdateTheme(colorScheme: ColorScheme) {
        let effective = configuration.paperStyle.resolvedTheme(colorScheme: colorScheme)
        configuration.theme = effective
        themeObservable.theme = effective.cosmosTheme
    }

    /// Switches the reader to a different paper style and re-renders live. Persists the choice.
    public func setPaperStyle(_ style: PaperStyle) {
        configuration.paperStyle = style
        settingsStore.save(currentSettings())
    }

    /// Switches the reader to a different theme (legacy v0.2 entry point; maps to a paper style).
    /// Persists the choice.
    public func setTheme(_ theme: MarklyReaderTheme) {
        configuration.paperStyle = PaperStyle.from(theme: theme)
        settingsStore.save(currentSettings())
    }

    /// Sets the reading mode (continuous / paged). Persists the choice.
    public func setReadingMode(_ mode: MarklyReadingMode) {
        configuration.readingMode = mode
        settingsStore.save(currentSettings())
    }

    /// Sets the font-size step. Persists the choice.
    public func setFontSize(_ size: MarklyFontSize) {
        configuration.fontSize = size
        settingsStore.save(currentSettings())
    }

    /// Sets the brightness (`0...1`). Persists the choice.
    public func setBrightness(_ brightness: Double) {
        configuration.brightness = min(1, max(0, brightness))
        settingsStore.save(currentSettings())
    }

    /// Sets the sticky last-used highlight color. Persists the choice.
    public func setLastHighlightColor(_ color: MarklyHighlightColor) {
        lastHighlightColor = color
        settingsStore.save(currentSettings())
    }

    /// Scrolls the reader to a section (e.g. from a TOC selection or a bookmark). Safe to call
    /// repeatedly; re-selecting the same section still scrolls.
    public func scrollTo(_ id: MarklySectionID) {
        let token = (scrollRequest?.token ?? 0) &+ 1
        scrollRequest = ScrollRequest(id: id, token: token)
    }

    // MARK: Chapters

    /// Sets the derived chapters and the section→chapter index map (called by the reader on load).
    public func setChapters(_ chapters: [MarklyChapter], sectionMap: [MarklySectionID: Int]) {
        self.chapters = chapters
        self.sectionToChapter = sectionMap
    }

    /// The chapter containing the current section, or `nil` if chapters are empty / unresolved.
    public var currentChapter: MarklyChapter? {
        guard let sectionID = currentSectionID,
              let index = sectionToChapter[sectionID],
              chapters.indices.contains(index) else { return nil }
        return chapters[index]
    }

    /// The title to show in the principal toolbar item: the current chapter's title, or the book
    /// title when there is no current chapter (e.g. before load or for a single-chapter book).
    public func principalTitle(for book: any MarklyBook) -> String {
        currentChapter?.title ?? book.title
    }

    /// Scrolls the reader to the start of the chapter at the given index (no-op if out of range).
    public func goToChapter(at index: Int) {
        guard chapters.indices.contains(index) else { return }
        scrollTo(chapters[index].firstBlockID)
    }

    /// Scrolls to the next chapter, if any.
    public func goToNextChapter() {
        guard let current = currentChapter,
              let index = chapters.firstIndex(of: current),
              index + 1 < chapters.count else { return }
        goToChapter(at: index + 1)
    }

    /// Scrolls to the previous chapter, if any.
    public func goToPreviousChapter() {
        guard let current = currentChapter,
              let index = chapters.firstIndex(of: current),
              index - 1 >= 0 else { return }
        goToChapter(at: index - 1)
    }

    // MARK: Reading position

    /// Saves the current section as the reading position for `book` (one position per book).
    public func saveCurrentPosition() async {
        guard let sectionID = currentSectionID else { return }
        let position = MarklyReadingPosition(id: book.id, sectionID: sectionID)
        try? await positionRepository.save(position)
    }

    /// Returns the saved reading position's section for `book`, if any. The reader restores it
    /// on load by scrolling to it.
    public func restorePosition() async -> MarklySectionID? {
        guard let position = try? await positionRepository.find(id: book.id) else { return nil }
        return position.sectionID
    }

    // MARK: Bookmarks

    /// Reloads the bookmarks for the current book from the repository (scans `stream()` filtered
    /// by `book.id` — the repository protocol exposes no query, per Nebula's design).
    public func refreshBookmarks() async {
        var collected: [MarklyBookmark] = []
        let stream = bookmarkRepository.stream()
        do {
            for try await bookmark in stream {
                if bookmark.bookID == book.id { collected.append(bookmark) }
            }
        } catch {
            // Repository read failure: show whatever we collected rather than fataling.
        }
        collected.sort { $0.createdAt < $1.createdAt }
        bookmarks = collected
    }

    /// `true` if a bookmark exists for the given section of the current book.
    public func isBookmarked(_ sectionID: MarklySectionID) -> Bool {
        bookmarks.contains { $0.sectionID == sectionID }
    }

    /// Bookmarks the current section (or a specific section). No-op if already bookmarked.
    public func addBookmark(at sectionID: MarklySectionID, title: String) async {
        guard !isBookmarked(sectionID) else { return }
        let bookmark = MarklyBookmark(bookID: book.id, sectionID: sectionID, title: title)
        try? await bookmarkRepository.save(bookmark)
        await refreshBookmarks()
    }

    /// Removes a bookmark by id.
    public func removeBookmark(_ id: UUID) async {
        try? await bookmarkRepository.delete(id)
        await refreshBookmarks()
    }

    // MARK: Highlights

    /// Reloads the highlights for the current book from the repository (filtered by `book.id`).
    public func refreshHighlights() async {
        var collected: [MarklyHighlight] = []
        let stream = highlightRepository.stream()
        do {
            for try await highlight in stream {
                if highlight.bookID == book.id { collected.append(highlight) }
            }
        } catch {
            // Repository read failure: show whatever we collected rather than fataling.
        }
        collected.sort { $0.createdAt < $1.createdAt }
        highlights = collected
    }

    /// The highlights anchored to a given section (block), in document order.
    public func highlights(for sectionID: MarklySectionID) -> [MarklyHighlight] {
        highlights.filter { $0.sectionID == sectionID }
    }

    /// Creates a highlight for the given section + character range using the sticky last-used
    /// color (updating it), persists it, and refreshes. Returns the created highlight.
    ///
    /// Idempotent + race-safe: if a highlight already covers this exact `sectionID` + `range`, it is
    /// returned instead of stacking a duplicate (a fast double-tap on the color button, or two
    /// concurrent `addHighlight` tasks, must not produce two highlights over the same text). The
    /// new entry is appended to `highlights` synchronously — before the first `await` — so a
    /// concurrent caller observing `highlights` while the save/refresh is suspended sees it and
    /// takes the existing-highlight path rather than creating a second.
    @discardableResult
    public func addHighlight(at sectionID: MarklySectionID, range: Range<Int>) async -> MarklyHighlight {
        if let existing = highlights.first(where: { $0.sectionID == sectionID && $0.range == range }) {
            return existing
        }
        let color = lastHighlightColor
        let highlight = MarklyHighlight(
            bookID: book.id, sectionID: sectionID, range: range, color: color
        )
        highlights.append(highlight)
        try? await highlightRepository.save(highlight)
        await refreshHighlights()
        return highlight
    }

    /// Changes the color of an existing highlight (sticky-color update) and persists it.
    public func setHighlightColor(_ color: MarklyHighlightColor, for id: UUID) async {
        guard let index = highlights.firstIndex(where: { $0.id == id }) else { return }
        highlights[index].color = color
        try? await highlightRepository.save(highlights[index])
        lastHighlightColor = color
        settingsStore.save(currentSettings())
        await refreshHighlights()
    }

    /// Sets or replaces the note attached to a highlight and persists it.
    public func setHighlightNote(_ note: String?, for id: UUID) async {
        guard let index = highlights.firstIndex(where: { $0.id == id }) else { return }
        highlights[index].note = note
        try? await highlightRepository.save(highlights[index])
        await refreshHighlights()
    }

    /// Removes a highlight by id.
    public func removeHighlight(_ id: UUID) async {
        try? await highlightRepository.delete(id)
        await refreshHighlights()
    }
}