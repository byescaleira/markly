# Markly

[![CI](https://github.com/byescaleira/markly/actions/workflows/ci.yml/badge.svg)](https://github.com/byescaleira/markly/actions/workflows/ci.yml)
[![Coverage](https://codecov.io/gh/byescaleira/markly/branch/main/graph/badge.svg)](https://codecov.io/gh/byescaleira/markly)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](./LICENSE)
[![Swift 6.4](https://img.shields.io/badge/Swift-6.4-orange.svg)](https://www.swift.org/)
![Release](https://img.shields.io/github/v/tag/byescaleira/markly?label=release)

> A SwiftUI markdown e-reader you drop into any Apple-platform app — chapters, multi-color highlights, an Apple-Books-style toolbar, themes, and share — built on the sibling [Nebula](https://github.com/byescaleira/nebula) and [Cosmos](https://github.com/byescaleira/cosmos) packages.

## Overview

Markly is a Swift Package that turns a markdown string into a long-form reading surface. One view call renders a book with:

- **Chapters** derived from top-level `#` headings, with previous/next navigation.
- **Free-form, multi-color highlights** (yellow / green / blue / pink / purple / underline) with notes, scoped per book and persisted.
- **An Apple-Books-style toolbar** — a top bar with the current chapter title + an overflow menu, and a bottom bar with contents, appearance (aA), highlights, and share.
- **Themes & settings** — font size, brightness, paper style (auto / white / sepia / night / dark), and scroll-vs-pages reading mode, persisted and restored on launch.
- **In-document search**, a **table of contents**, and **bookmarks**.
- An **Apple-only stack**: parsed with [apple/swift-markdown](https://github.com/apple/swift-markdown), inlined with Foundation `AttributedString(markdown:)`, and rendered through a vendored slice of [gonzalezreal/swift-markdown-ui](https://github.com/gonzalezreal/swift-markdown-ui) (MIT — see [Acknowledgements](#acknowledgements)). No third-party markdown *parsing* dependency; MarkdownUI's parser is Apple's own cmark, the same engine behind `apple/swift-markdown`.

It targets **iOS, macOS, tvOS, and visionOS 26** (deliberately no watchOS — a long-form reader's chrome does not fit a watch). Swift 6, strict concurrency.

## Requirements

- iOS 26 / macOS 26 / tvOS 26 / visionOS 26
- Swift 6 (swift-tools 6.3)
- Xcode 26 (builds clean on Xcode 27 / Swift 6.4 too)

## Installation

Add Markly as a package dependency:

```swift
dependencies: [
    .package(url: "https://github.com/byescaleira/markly.git", from: "0.5.0")
]
```

and add it to your target:

```swift
.target(
    name: "YourApp",
    dependencies: [
        .product(name: "Markly", package: "markly")
    ]
)
```

## Getting started

```swift
import SwiftUI
import Markly

struct ContentView: View {
    var body: some View {
        MarklyReader(
            book: MarklyLiteralBook(
                title: "The Art of the Long Read",
                markdown: """
                # Chapter One

                Markdown renders as a native SwiftUI reading surface.

                ## A section

                - Lists, **bold**, *italics*, ~~strikethrough~~, `code`, [links](https://example.com)
                - Code blocks, block quotes, tables, and images
                """
            )
        )
    }
}
```

`MarklyReader(book:)` accepts anything conforming to the `MarklyBook` protocol — `MarklyLiteralBook` for an in-memory string, or your own type whose `source()` is `async` (fetch from disk, a bundle, or the network). Pass a `MarklyConfiguration` to toggle features, or a pre-built `MarklyReaderController` to own the reader's state externally.

## Features

### Chapters

Top-level `#` headings become chapters. Blocks before the first `#` form an implicit "Start of document" chapter; a document with no `#` is a single implicit chapter. The current chapter title shows in the top bar; jump between chapters from the overflow menu.

### Highlights

Select any text (iOS / iPadOS / visionOS / macOS) to open the highlight action bar: pick a marker color or underline, add a note, or remove. Highlights are scoped per book and persisted through a pluggable repository. The sticky color is remembered across highlights. On tvOS there is no text selection, so highlights are view-only (the list + excerpts).

### Themes & settings

The **aA** appearance sheet exposes font size (discrete Apple-Books-style steps), brightness, paper style (auto follows the system appearance), and reading mode (scroll vs. pages). All choices are persisted and restored on launch, overriding a seeded configuration.

### Search, contents, and bookmarks

In-document search (case / whole-word options, debounced and off the main actor), a table of contents, and per-book bookmarks round out the reader.

## Platform adaptation

Markly uses only cross-platform toolbar primitives: the bottom bar is a `safeAreaInset` (not the iOS-only `.bottomBar` placement), and the overflow menu uses `.primaryAction`. Where a control is unavailable on a platform it degrades gracefully — tvOS has no `Slider`/`Stepper`, so font size uses a `Picker` there and brightness is omitted; tvOS paragraphs use `Text` (no selection). The full per-platform notes live in [`docs/Architecture.md`](./docs/Architecture.md) §10.7.

## Architecture

Markly keeps a **Domain** layer (Foundation-only: block/inline model, parser, search, chapters, highlights, settings) separate from its **Rendering** layer (SwiftUI block renderers + the selectable-text highlight surface), glued by a `@MainActor @Observable` `MarklyReaderController`. It composes the sibling **Nebula** (Clean Architecture primitives, errors, instrumentation, preferences) and **Cosmos** (SwiftUI design-system atoms + theme tokens). See [`docs/Architecture.md`](./docs/Architecture.md) for the as-built design.

## Development

```bash
swift build
swift test
# Verify the non-host platforms:
xcodebuild -scheme Markly -destination 'generic/platform=iOS Simulator' build
xcodebuild -scheme Markly -destination 'generic/platform=tvOS Simulator' build
xcodebuild -scheme Markly -destination 'generic/platform=visionOS Simulator' build
```

## Versioning

Markly follows [Semantic Versioning](https://semver.org) while below 1.0 (0.x.y): minors may add features or change behavior, patches are fixes. The deployment floor (Apple OS 26) is tracked separately in `Package.swift` and is independent of the package version. See [`VERSIONING.md`](./VERSIONING.md).

## Governance

This is a personal project by Rafael Escaleira. Branching follows gitflow:

- `main` — stable releases only
- `develop` — integration branch
- `feature/<name>`, `fix/<name>` — work branches
- `release/<x.y.z>` — release preparation

See [`CONTRIBUTING.md`](./CONTRIBUTING.md) for the release process.

## License

MIT — see [`LICENSE`](./LICENSE).

## Acknowledgements

Markly's markdown **rendering layer** — the block/inline views, the `Theme`/`BlockStyle`/`TextStyle`
system, and the `BlockNode`/`InlineNode` AST used to render headings, code blocks, thematic breaks,
and HTML blocks — is built using code from [gonzalezreal/swift-markdown-ui](https://github.com/gonzalezreal/swift-markdown-ui)
("MarkdownUI"), MIT-licensed with **Copyright (c) 2020 Guillermo Gonzalez**. That code is vendored
into [`Sources/MarkdownUI/`](./Sources/MarkdownUI/) and its verbatim MIT notice is preserved in
[`Sources/MarkdownUI/LICENSE`](./Sources/MarkdownUI/LICENSE).

Markly does not use MarkdownUI as a package dependency. Only the rendering engine is vendored;
the cmark-based `MarkdownParser` and the programmatic DSL were not vendored. Markly parses with
Apple's [`apple/swift-markdown`](https://github.com/apple/swift-markdown), converts its own
`MarklyBlock` AST into MarkdownUI's `BlockNode`, and renders the leaf blocks through the vendored
views. Paragraphs, block quotes, lists, tables, and block directives stay on Markly's own renderer
so selectable-text highlights keep working at every nesting level. See
[`docs/Architecture.md`](./docs/Architecture.md) §3 for the as-built split.