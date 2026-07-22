//
//  MarklyConfiguration.swift
//  Markly
//
//  Reader configuration: theme, reading mode, feature toggles, and an in-app URL predicate.
//  Deliberately `Sendable` (not `Equatable`) because `openURLInApp` is a closure.
//

import Foundation

/// How the reading surface advances.
public enum MarklyReadingMode: String, Sendable, Equatable, CaseIterable, Codable {
    /// Continuous vertical scroll (default).
    case continuous
    /// Paginated, one screen-height page at a time via `.scrollTargetBehavior(.paging)`.
    case paged
}

/// Toggles for optional reader features.
public struct MarklyFeatures: Sendable, Equatable {
    /// Shows a table of contents built from headings (Phase 2).
    public var tableOfContents: Bool
    /// In-document search (Phase 2).
    public var search: Bool
    /// Bookmarks (Phase 2).
    public var bookmarks: Bool
    /// Share action (Phase 2; v0.3 wires the UI).
    public var share: Bool
    /// Multi-color highlights over selectable text (v0.3). No creation on tvOS (no text
    /// selection); existing highlights remain view-only there.
    public var highlights: Bool
    /// Chapter navigation derived from top-level (`#`) headings (v0.3).
    public var chapters: Bool
    /// The Themes & Settings (aA) panel: font size, brightness, paper style (v0.3).
    public var settingsPanel: Bool

    /// All features enabled.
    public static let all = MarklyFeatures()
    /// All features disabled.
    public static let none = MarklyFeatures(
        tableOfContents: false, search: false, bookmarks: false, share: false,
        highlights: false, chapters: false, settingsPanel: false
    )

    /// Creates a feature set.
    public init(
        tableOfContents: Bool = true,
        search: Bool = true,
        bookmarks: Bool = true,
        share: Bool = true,
        highlights: Bool = true,
        chapters: Bool = true,
        settingsPanel: Bool = true
    ) {
        self.tableOfContents = tableOfContents
        self.search = search
        self.bookmarks = bookmarks
        self.share = share
        self.highlights = highlights
        self.chapters = chapters
        self.settingsPanel = settingsPanel
    }
}

/// Configuration for a `MarklyReader`.
public struct MarklyConfiguration: Sendable {
    /// The reader color theme (seeded default; the user's persisted `paperStyle` overrides it on
    /// launch). Kept for back-compat; `paperStyle` is the richer, user-facing selector.
    public var theme: MarklyReaderTheme
    /// The reading mode.
    public var readingMode: MarklyReadingMode
    /// Feature toggles.
    public var features: MarklyFeatures
    /// Returns `true` for URLs that should be routed in-app (everything else goes to the system).
    public var openURLInApp: @Sendable (URL) -> Bool
    /// The reader's paper (background) style. `.auto` follows the system appearance. Seeded
    /// default `.auto`; the user's persisted choice overrides it on launch.
    public var paperStyle: PaperStyle
    /// The reader's discrete font-size step. Seeded default `.large`; the persisted choice
    /// overrides it on launch.
    public var fontSize: MarklyFontSize
    /// The reader's brightness, `0...1` (1 = full). Drives a cross-platform dimming overlay; the
    /// persisted choice overrides the seeded default on launch.
    public var brightness: Double

    /// The default configuration: auto paper, default font, full brightness, continuous mode, all
    /// features, no in-app URLs.
    public static let `default` = MarklyConfiguration()

    /// Creates a configuration.
    public init(
        theme: MarklyReaderTheme = .light,
        readingMode: MarklyReadingMode = .continuous,
        features: MarklyFeatures = .all,
        openURLInApp: @escaping @Sendable (URL) -> Bool = { _ in false },
        paperStyle: PaperStyle = .auto,
        fontSize: MarklyFontSize = .default,
        brightness: Double = 1.0
    ) {
        self.theme = theme
        self.readingMode = readingMode
        self.features = features
        self.openURLInApp = openURLInApp
        self.paperStyle = paperStyle
        self.fontSize = fontSize
        self.brightness = brightness
    }
}