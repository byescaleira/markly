## Contributing

1. Respect the layer split: **Domain** (Foundation-only — model, parser, search, chapters, highlights, settings) must not import SwiftUI; **Rendering** is the SwiftUI layer. Glue lives in `MarklyReaderController`.
2. Keep the Apple-only stack: parse with `apple/swift-markdown`, inline with Foundation `AttributedString(markdown:)` / `NSAttributedString(markdown:options:)`. No third-party markdown dependencies.
3. Gate platform-unavailable APIs (`#if !os(tvOS)`, `#if os(macOS)`, …) rather than leaving cross-platform gaps. See `docs/Architecture.md` §10.7 for the known platform divergences.
4. Document public APIs.
5. Add Swift Testing / XCTest unit tests for Domain behavior. Use `#Preview` for visual validation of Rendering.
6. Maintain backward compatibility for a minor release after deprecation (see `VERSIONING.md`).

## Branching

- `main` — stable releases only
- `develop` — integration branch
- `feature/<name>` — new components
- `fix/<name>` — bug fixes
- `release/<x.y.z>` — release preparation

## Release Process

1. Bump the version in `Sources/Markly/Markly.swift` (`Markly.version`) **and** the `.package(url:…, from: "X.Y.Z")` line in `README.md`.
2. Update `CHANGELOG.md` (`## [Unreleased]` → `## [X.Y.Z] - YYYY-MM-DD`).
3. Tag release `X.Y.Z`.
4. Merge `release/<x.y.z>` to `main` with a `chore(release): X.Y.Z` commit.