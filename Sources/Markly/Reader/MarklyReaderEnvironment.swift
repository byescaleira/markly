//
//  MarklyReaderEnvironment.swift
//  Markly
//
//  Environment values the reading surface injects so leaf block views can render v0.3 features
//  (highlights, font size) without a direct dependency on `MarklyReaderController`. Each defaults
//  to a no-op / neutral value so `MarklyBlockView` still renders standalone (e.g. in previews and
//  tests).
//
//  Mirrors `marklySectionObserver`: the closures are `@MainActor`-isolated so they are `Sendable`
//  and satisfy Swift 6 strict concurrency as `EnvironmentKey` defaults.
//

import SwiftUI

private struct MarklyReaderFeaturesKey: EnvironmentKey {
    static let defaultValue: MarklyFeatures = .all
}

private struct MarklyReaderFontSizeKey: EnvironmentKey {
    static let defaultValue: MarklyFontSize = .default
}

private struct MarklyHighlightsProviderKey: EnvironmentKey {
    static let defaultValue: @MainActor (MarklySectionID) -> [MarklyHighlight] = { _ in [] }
}

private struct MarklySelectionObserverKey: EnvironmentKey {
    static let defaultValue: @MainActor (MarklySectionID, Range<Int>?) -> Void = { _, _ in }
}

extension EnvironmentValues {
    /// The reader's feature toggles (drives whether paragraphs render as selectable text).
    var marklyReaderFeatures: MarklyFeatures {
        get { self[MarklyReaderFeaturesKey.self] }
        set { self[MarklyReaderFeaturesKey.self] = newValue }
    }

    /// The reader's current font-size step (drives the selectable text view's font scaling).
    var marklyReaderFontSize: MarklyFontSize {
        get { self[MarklyReaderFontSizeKey.self] }
        set { self[MarklyReaderFontSizeKey.self] = newValue }
    }

    /// Returns the highlights anchored to a given section (block), used to render highlight
    /// backgrounds/underlines inline.
    var marklyHighlightsProvider: @MainActor (MarklySectionID) -> [MarklyHighlight] {
        get { self[MarklyHighlightsProviderKey.self] }
        set { self[MarklyHighlightsProviderKey.self] = newValue }
    }

    /// Reports a paragraph's text selection (as a character range into the block's plain text, or
    /// `nil` when the selection is cleared) so the reader can surface the highlight color toolbar.
    var marklySelectionObserver: @MainActor (MarklySectionID, Range<Int>?) -> Void {
        get { self[MarklySelectionObserverKey.self] }
        set { self[MarklySelectionObserverKey.self] = newValue }
    }
}