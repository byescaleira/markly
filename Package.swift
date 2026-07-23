// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.
// Set to 6.3 so the package builds on Xcode 26.4+ (Swift 6.3) and Xcode 27 (Swift 6.4), matching
// the Nebula and Cosmos sibling packages. Any OS-27-only SDK symbol is compile-gated with
// `#if swift(>=6.4)` so it compiles to a graceful fallback on Swift 6.3 and turns on under
// Xcode 27 / Swift 6.4.
//
// Markly is a SwiftUI markdown e-reader. It renders markdown and provides e-reader
// functionality (TOC, scroll/pagination, bookmarks, reading-position persistence, reader
// themes) and is pluggable into any app with `import Markly` + one `MarklyReader` view call.
// It is built on two sibling local packages:
//   - Nebula  (Foundation-only Clean Architecture spine: UseCase, Repository, Preferences, …)
//   - Cosmos  (SwiftUI design-system: atoms + theme tokens)
// and parses markdown exclusively with Apple's official `apple/swift-markdown` (`Markdown`
// module). No third-party markdown parser/renderer is permitted (see docs/Architecture.md).

import PackageDescription

let package = Package(
    name: "Markly",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v26),
        .macOS(.v26),
        .tvOS(.v26),
        .visionOS(.v26),
        // NOT watchOS: Markly is a long-form reader whose chrome depends on a ScrollView +
        // focusable-anchor surface that does not fit watchOS. Deliberate divergence from
        // Nebula/Cosmos (which include watchOS). See docs/Architecture.md §1.
    ],
    products: [
        .library(
            name: "Markly",
            targets: ["Markly"]
        ),
    ],
    dependencies: [
        // Sibling foundation/architecture layer (Foundation-only, no SwiftUI). Published on GitHub
        // as `byescaleira/nebula`; pinned to a versioned release so external consumers resolve it
        // without a local checkout. For lockstep local development, use a path override
        // (`.package(path: "../nebula")`) or `swift package edit nebula`.
        .package(url: "https://github.com/byescaleira/nebula.git", from: "0.18.0"),
        // Sibling SwiftUI design system (atoms + theme tokens + modifiers). Published on GitHub as
        // `byescaleira/cosmos`; pinned to a versioned release. See the override note above.
        .package(url: "https://github.com/byescaleira/cosmos.git", from: "0.2.0"),
        // Apple's official Markdown parser. Module name is `Markdown`. Platform-agnostic
        // (Foundation/stdlib only), so it composes cleanly with the .v26 deployment floor.
        // The `apple/swift-markdown` mirror publishes semver tags (0.8.0 is current).
        .package(url: "https://github.com/apple/swift-markdown.git", from: "0.8.0"),
    ],
    targets: [
        // Vendored rendering layer from gonzalezreal/swift-markdown-ui (MIT; Copyright (c) 2020
        // Guillermo Gonzalez). Only the rendering engine is vendored — the block/inline views,
        // the Theme/BlockStyle/TextStyle system, and the AttributedString inline renderer. The
        // cmark-based `MarkdownParser` and the programmatic DSL are NOT vendored: Markly parses
        // with Apple's `apple/swift-markdown` and converts its `MarklyBlock` AST into MarkdownUI's
        // `BlockNode` (single parse → highlight ranges align with the rendered text). The
        // `NetworkImage` package is NOT vendored: Markly wires MarkdownUI's `ImageProvider`
        // protocol to the existing `MarklyRemoteImage`. See Sources/MarkdownUI/LICENSE for the
        // preserved MIT notice and README "Acknowledgements" for the credit.
        .target(
            name: "MarkdownUI",
            path: "Sources/MarkdownUI",
            exclude: ["LICENSE"],
            // The vendored rendering layer stays at the Swift 5 language mode: gonzalezreal/
            // swift-markdown-ui was written for Swift 5.6, and its Theme/BlockStyle/TextStyle
            // closures and SwiftUI View initializers (e.g. `BlockStyle { Divider() }`) are not
            // Swift 6 strict-concurrency-annotated — porting every closure to @MainActor/@Sendable
            // would be a deep, fragile change to upstream code we want to keep close to vendored.
            // Markly's own code stays at .v6 strict (the package default); only this vendored
            // third-party target is .v5, the standard practice for vendoring a Swift-5 library.
            // Markly consumes MarkdownUI entirely on the MainActor (rendering happens in View
            // bodies), so no non-Sendable value crosses an actor boundary.
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .target(
            name: "Markly",
            dependencies: [
                .product(name: "Nebula", package: "nebula"),
                .product(name: "Cosmos", package: "cosmos"),
                .product(name: "Markdown", package: "swift-markdown"),
                .target(name: "MarkdownUI"),
            ],
            resources: [
                // Reader-facing UI strings (String Catalog). `.process` compiles
                // Localizable.xcstrings → .lproj/.strings at build time; `Bundle.module`
                // exposes it at runtime (defaultLocalization above is already set). Markly
                // localizes reader chrome (TOC labels, "Copy code", loading/error strings).
                .process("Resources"),
            ]
        ),
        .testTarget(
            name: "MarklyTests",
            dependencies: ["Markly"],
            resources: [
                // Bundled sample markdown fixtures for parse/render round-trip tests and
                // #Preview content. Read via `Bundle.module`.
                .process("Fixtures"),
            ],
        ),
    ],
    swiftLanguageModes: [.v6]
)