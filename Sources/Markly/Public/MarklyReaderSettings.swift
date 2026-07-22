//
//  MarklyReaderSettings.swift
//  Markly
//
//  Persisted reader preferences — theme/paper style, reading mode, font size, brightness, and
//  the last-used highlight color — backed by `NebulaPreferences`. A small JSON blob under one key,
//  shared across all books (reader appearance settings are global, not per-book, in v0.3).
//  `MarklyReaderController` loads these on init (overriding the seeded configuration with the
//  user's last choice) and re-saves them whenever a `setX(_:)` method is called.
//
//  Codable uses `decodeIfPresent` everywhere so existing installs (which stored only `theme` +
//  `readingMode`) migrate cleanly: a legacy `theme` is round-tripped into the new `paperStyle`.
//

import Foundation
import Nebula

/// Persisted reader preferences.
public struct MarklyReaderSettings: Codable, Sendable, Equatable {
    /// The reading mode (continuous / paged).
    public var readingMode: MarklyReadingMode
    /// The reader's paper (background) style.
    public var paperStyle: PaperStyle
    /// The reader's font-size step.
    public var fontSize: MarklyFontSize
    /// The reader's brightness (`0...1`).
    public var brightness: Double
    /// The last-used highlight color (Apple Books' sticky-color behavior).
    public var lastHighlightColor: MarklyHighlightColor

    /// Creates settings.
    public init(
        readingMode: MarklyReadingMode = .continuous,
        paperStyle: PaperStyle = .auto,
        fontSize: MarklyFontSize = .default,
        brightness: Double = 1.0,
        lastHighlightColor: MarklyHighlightColor = .yellow
    ) {
        self.readingMode = readingMode
        self.paperStyle = paperStyle
        self.fontSize = fontSize
        self.brightness = brightness
        self.lastHighlightColor = lastHighlightColor
    }

    /// The defaults used when nothing is persisted yet.
    public static let `default` = MarklyReaderSettings()

    private enum CodingKeys: String, CodingKey {
        case readingMode, paperStyle, fontSize, brightness, lastHighlightColor
        case theme // legacy v0.2 key, migrated into paperStyle
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.readingMode = try c.decodeIfPresent(MarklyReadingMode.self, forKey: .readingMode) ?? .continuous
        self.fontSize = try c.decodeIfPresent(MarklyFontSize.self, forKey: .fontSize) ?? .default
        self.brightness = try c.decodeIfPresent(Double.self, forKey: .brightness) ?? 1.0
        self.lastHighlightColor = try c.decodeIfPresent(MarklyHighlightColor.self, forKey: .lastHighlightColor) ?? .yellow
        if let paper = try c.decodeIfPresent(PaperStyle.self, forKey: .paperStyle) {
            self.paperStyle = paper
        } else if let legacyTheme = try c.decodeIfPresent(MarklyReaderTheme.self, forKey: .theme) {
            // Migrate a v0.2 `theme` into the new `paperStyle`.
            self.paperStyle = PaperStyle.from(theme: legacyTheme)
        } else {
            self.paperStyle = .auto
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(readingMode, forKey: .readingMode)
        try c.encode(paperStyle, forKey: .paperStyle)
        try c.encode(fontSize, forKey: .fontSize)
        try c.encode(brightness, forKey: .brightness)
        try c.encode(lastHighlightColor, forKey: .lastHighlightColor)
    }
}

/// A `NebulaPreferences`-backed store for `MarklyReaderSettings`. Stateless, so `Sendable`.
public final class MarklyReaderSettingsStore: Sendable {
    private let prefs: NebulaPreferences
    private let key: String

    /// Creates a store. Defaults to Markly's shared `NebulaPreferences` and the standard key.
    public init(
        prefs: NebulaPreferences = MarklyDefaultRepositories.preferences,
        key: String = "markly.reader.settings"
    ) {
        self.prefs = prefs
        self.key = key
    }

    /// Loads persisted settings, or `nil` if nothing is stored yet (so the caller can keep its
    /// seeded configuration on first launch).
    public func load() -> MarklyReaderSettings? {
        try? prefs.value(MarklyReaderSettings.self, forKey: key)
    }

    /// Persists settings.
    public func save(_ settings: MarklyReaderSettings) {
        try? prefs.setValue(settings, forKey: key)
    }
}