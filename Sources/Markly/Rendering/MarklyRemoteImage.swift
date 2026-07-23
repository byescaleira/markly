//
//  MarklyRemoteImage.swift
//  Markly
//
//  A remote markdown image (`![alt](url)`) rendered at its intrinsic aspect ratio. This replaces
//  the prior `CosmosAsyncImage` path, which collapsed images to zero height: `AsyncImage`'s content
//  closure (`image.resizable().scaledToFit()`) inside a `.frame(maxWidth: .infinity)` vertical stack
//  has no concrete intrinsic size to anchor `scaledToFit`, so SwiftUI proposes a zero height.
//
//  The fix (the MarkdownUI `NetworkImage` technique): fetch the bytes with `URLSession`, decode to
//  a platform image (`UIImage`/`NSImage`) which carries an intrinsic size, then
//  `Image.resizable().scaledToFit()` sizes reliably to the container width with a height of
//  `width / aspectRatio`. Apple-only: no third-party image cache. See docs/Architecture.md §3, §10.
//
//  Concurrency: `.task(id: source)` cancels the previous fetch and starts a new one when the source
//  changes (LazyVStack recycling). A stale fetch can outlive its cancellation and otherwise clobber
//  the live state (wrong-image race, or a `CancellationError` overwriting a valid image with the
//  failure placeholder). A monotonic generation token guards every phase mutation: only the
//  current generation may write. The token is bumped and `phase` reset to `.loading` at the start
//  of each task, so a recycled view also shows the loading state for the new URL (not the stale
//  image/placeholder).
//

import SwiftUI
import Cosmos

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// A remote image loaded via `URLSession` and rendered at its natural aspect ratio.
struct MarklyRemoteImage: View {
    /// The image source URL string (the `![alt](source)` destination).
    let source: String
    /// The alt text, used as the accessibility label.
    let alt: String

    @Environment(\.cosmosTheme) private var theme

    @State private var phase: Phase = .loading
    /// Monotonic token bumped on each `.task(id:)` invocation; stale fetches compare-and-bail.
    @State private var generation: Int = 0

    private enum Phase {
        case loading
        case success(PlatformImage)
        case failure
    }

    var body: some View {
        Group {
            switch phase {
            case .loading:
                placeholder
            case .success(let image):
                platformImage(image)
                    .resizable()
                    .scaledToFit()
            case .failure:
                failureView
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: themeRadius, style: .continuous))
        .accessibilityLabel(alt)
        .task(id: source) {
            // `.task` runs on the main actor (view context). Bump the generation and reset to the
            // loading state so a recycled view doesn't keep showing the previous source's image.
            generation &+= 1
            phase = .loading
            await load(generation: generation)
        }
    }

    /// A modest corner radius for inline/block images (smaller than the code card).
    private var themeRadius: CGFloat { 8 }

    @ViewBuilder
    private var placeholder: some View {
        RoundedRectangle(cornerRadius: themeRadius, style: .continuous)
            .fill(theme.colors.surface)
            .frame(height: 120)
            .overlay {
                ProgressView()
                    .tint(theme.colors.secondary)
            }
    }

    @ViewBuilder
    private var failureView: some View {
        RoundedRectangle(cornerRadius: themeRadius, style: .continuous)
            .fill(theme.colors.surface)
            .frame(height: 120)
            .overlay {
                Image(systemName: "photo")
                    .font(.system(size: 28))
                    .foregroundStyle(theme.colors.secondary)
            }
    }

    /// Decodes the fetched data into a platform image.
    private func platformImage(_ image: PlatformImage) -> Image {
        #if os(macOS)
        return Image(nsImage: image)
        #else
        return Image(uiImage: image)
        #endif
    }

    /// Loads the image bytes off the main actor and decodes them. Only commits a phase change if
    /// `token` is still the current generation — a stale (cancelled or superseded) fetch is dropped.
    private func load(generation token: Int) async {
        guard let url = URL(string: source) else {
            await commit(.failure, token: token)
            return
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let image = PlatformImage(data: data) else {
                await commit(.failure, token: token)
                return
            }
            await commit(.success(image), token: token)
        } catch {
            // A cancelled fetch throws here; the commit is a no-op for a stale token, so
            // cancellation never clobbers a newer load with the failure placeholder.
            await commit(.failure, token: token)
        }
    }

    /// Commits a phase change on the main actor only if the fetch is still current. Uses
    /// `MainActor.run` (async by declaration) so the hops don't trip the unnecessary-await warning.
    private func commit(_ next: Phase, token: Int) async {
        await MainActor.run {
            guard token == generation else { return }
            phase = next
        }
    }
}

// MARK: - Platform image bridge

#if os(macOS)
private typealias PlatformImage = NSImage
#else
private typealias PlatformImage = UIImage
#endif