//
//  MarklyMarkdownUIImageProviders.swift
//
//  Markly-backed implementations of MarkdownUI's image-provider protocols, so any image that
//  reaches MarkdownUI's vendored inline/block image views (e.g. an image inside a heading) loads
//  through Markly's own Apple-only `URLSession` path rather than the vendored default. In
//  practice the image-bearing block — the paragraph — stays on Markly's selectable path
//  (`MarklyInlineText` / `MarklyRichInlineContent` → `MarklyRemoteImage`), so these providers are
//  exercised only for the rare image-inside-a-heading case; they exist to keep image loading
//  coherent and Apple-only across the whole rendering tree. See docs/Architecture.md §3, §10.
//

import SwiftUI
import MarkdownUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// A MarkdownUI `InlineImageProvider` that loads inline images with `URLSession` (Apple-only,
/// no third-party cache). Used for images that appear inside a line of MarkdownUI-rendered text
/// (rare in Markly: an image inside a heading). The image-bearing paragraph stays on Markly's
/// selectable path, which renders images via `MarklyRichInlineContent` → `MarklyRemoteImage`
/// (with the alt text as an accessibility label).
struct MarklyInlineImageProvider: InlineImageProvider {
    func image(with url: URL, label: String) async throws -> Image {
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let platform = MarklyPlatformImage.Image(data: data) else {
            throw MarklyInlineImageError.invalidData
        }
        // `Image(uiImage:scale:label:)` does not resolve on iOS/tvOS/visionOS (falls back to the
        // `CGImage` positional init), so use the single-arg init. The alt-text label cannot be
        // attached to a bare `Image` returned from this protocol; the paragraph path carries it.
        _ = label
        return MarklyPlatformImage.image(platform)
    }
}

private enum MarklyInlineImageError: Error {
    case invalidData
}

extension InlineImageProvider where Self == MarklyInlineImageProvider {
    /// The Markly inline image provider (`URLSession`-backed, Apple-only).
    static var markly: Self { MarklyInlineImageProvider() }
}

// MARK: - Platform image bridge

private enum MarklyPlatformImage {
    #if os(macOS)
    typealias Image = NSImage
    #else
    typealias Image = UIImage
    #endif

    static func image(_ platform: Image) -> SwiftUI.Image {
        #if os(macOS)
        return SwiftUI.Image(nsImage: platform)
        #else
        return SwiftUI.Image(uiImage: platform)
        #endif
    }
}