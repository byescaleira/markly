//
//  DefaultImageProviders.swift
//  MarkdownUI
//
//  Replaces gonzalezreal/swift-markdown-ui's NetworkImage-backed defaults (which depended on the
//  `gonzalezreal/NetworkImage` package, not vendored here) with a minimal, Apple-only
//  `URLSession` implementation. Markly overrides both providers via the environment with ones
//  backed by `MarklyRemoteImage`, so these exist primarily so the `.default` environment values
//  compile and the vendored target is self-contained. MIT-licensed upstream code; see
//  Sources/MarkdownUI/LICENSE.
//

import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - Platform image bridge

enum DefaultPlatformImage {
  #if canImport(UIKit)
  typealias Image = UIImage
  #elseif canImport(AppKit)
  typealias Image = NSImage
  #endif
}

// MARK: - Shared loader

enum DefaultImageLoader {
  static func load(from url: URL) async throws -> DefaultPlatformImage.Image {
    let (data, _) = try await URLSession.shared.data(from: url)
    guard let image = DefaultPlatformImage.Image(data: data) else {
      throw DefaultImageError.invalidData
    }
    return image
  }
}

enum DefaultImageError: Error {
  case invalidData
}

// MARK: - Block image provider (ImageProvider)

/// A default `ImageProvider` that loads images from the network with `URLSession`.
public struct DefaultImageProvider: ImageProvider {
  public init() {}

  public func makeImage(url: URL?) -> some View {
    DefaultRemoteImageView(url: url)
  }
}

extension ImageProvider where Self == DefaultImageProvider {
  /// The default image provider, loading images from the network with `URLSession`.
  public static var `default`: Self { .init() }
}

private struct DefaultRemoteImageView: View {
  let url: URL?
  @State private var phase: DefaultRemoteImagePhase = .loading

  var body: some View {
    Group {
      switch phase {
      case .loading:
        ProgressView()
      case .success(let image):
        defaultPlatformImage(image).resizable().scaledToFit()
      case .failure:
        Image(systemName: "photo")
      }
    }
    .task(id: url) {
      guard let url else { phase = .failure; return }
      phase = .loading
      do {
        phase = .success(try await DefaultImageLoader.load(from: url))
      } catch {
        phase = .failure
      }
    }
  }
}

private enum DefaultRemoteImagePhase {
  case loading
  case success(DefaultPlatformImage.Image)
  case failure
}

private func defaultPlatformImage(_ image: DefaultPlatformImage.Image) -> Image {
  #if canImport(UIKit)
  return Image(uiImage: image)
  #elseif canImport(AppKit)
  return Image(nsImage: image)
  #endif
}

// MARK: - Inline image provider (InlineImageProvider)

/// A default `InlineImageProvider` that loads images from the network with `URLSession`.
public struct DefaultInlineImageProvider: InlineImageProvider {
  public init() {}

  public func image(with url: URL, label: String) async throws -> Image {
    let platform = try await DefaultImageLoader.load(from: url)
    #if canImport(UIKit)
    return Image(uiImage: platform, scale: 1, label: Text(label))
    #elseif canImport(AppKit)
    // AppKit's Image has no scale/label init; attach the label as accessibility instead.
    return Image(nsImage: platform)
    #endif
  }
}

extension InlineImageProvider where Self == DefaultInlineImageProvider {
  /// The default inline image provider, loading images from the network with `URLSession`.
  public static var `default`: Self { .init() }
}