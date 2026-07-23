# Changelog

All notable changes to Markly are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to
[Semantic Versioning](https://semver.org) (relaxed pre-1.0 form).

## [Unreleased]

## [0.4.0] - 2026-07-22

A top-to-bottom rendering overhaul that brings the reading surface to GitHub-markdown quality,
adapted from the [MarkdownUI](https://github.com/gonzalezreal/swift-markdown-ui) GitHub-theme
recipes into Markly's architecture (the `apple/swift-markdown` parser, Markly's block/inline AST,
selectable-text highlights, and Cosmos tokens are all preserved). 85 passing tests; builds clean
on iOS, macOS, tvOS, and visionOS 26.

### Added

- **`MarklyMarkdownTheme`** — a color-free markdown layout/typography theme (colors stay Cosmos-driven
  so paper styles still adapt), layered over `@Environment(\.cosmosTheme)`. Holds per-level heading
  sizes/weights, the gap-before spacing engine, list markers/indentation, and code/table geometry.
  Injected via `@Environment(\.marklyMarkdownTheme)` with a `.github` default.
- **`marklyFont(size:weight:)`** — a `@ScaledMetric`-based font modifier (mirrors MarkdownUI's
  `ScaledFontSizeModifier`) so headings, list markers, code, and table text scale with the aA
  font-size slider, not just the system Dynamic Type setting.
- **`MarklyBlockSequence`** — the block-stacking primitive: a zero-spacing stack with a per-block
  *gap-before* padding. A deliberate `LazyVStack`-compatible alternative to MarkdownUI's
  preference-key `BlockSequence` (which doesn't compose with lazy loading for long books). Tight
  mode drives compact spacing inside list items and block quotes.
- **`MarklyRemoteImage`** — a `URLSession`-based remote image that decodes to `UIImage`/`NSImage`
  (carrying an intrinsic size) and renders `resizable().scaledToFit()`. Replaces the
  `CosmosAsyncImage` path, which collapsed images to zero height. Guarded by a monotonic generation
  token so a stale (cancelled or superseded) fetch can't clobber the live image, and resets to the
  loading state when a recycled view's source changes.

### Changed

- **Headings are now bold and proportionally sized.** Root cause was Cosmos `font(for:)` returning
  weightless `.system(textStyle)`; headings now render at `.system(size:weight:.semibold)` per
  level (h1 32pt → h6 14pt, all semibold), with h1/h2 carrying a bottom divider. Inline code inside a
  heading or semibold table header now matches the surrounding size/weight (SwiftUI renders
  `AttributedString` `.code` runs with a monospaced font that bypasses the `.font` modifier, so
  code runs are given an explicit monospaced font matching the base size/weight).
- **Lists now nest properly.** Unordered markers cycle by depth (disc → circle → square), ordered
  markers use `.monospacedDigit()` with trailing alignment, each nesting depth indents, and a
  `marklyListDepth` environment threads depth through nested lists. Item rows align the marker to
  the first text baseline, or to the top when the item leads with an image.
- **Tables render the GitHub look.** A `Grid` with the gutter-fill border technique (the Grid's own
  background is the border color, cell spacing equals the border width, opaque row backgrounds mask
  it except in the gutters), alternating row backgrounds, a semibold header, and per-column
  alignment — robust inside a `LazyVStack` without anchor-preference measurement.
- **Block quotes** render through `MarklyBlockSequence(tight: true)` for compact nested spacing.
- **iOS 26 Liquid Glass** on the floating highlight toolbar via `.glassEffect(.regular, in:)` on
  iOS/macOS/tvOS 26 (the symbol is `@available(visionOS, unavailable)`, so visionOS keeps the
  translucent surface-card fallback). Verified against the SwiftUICore `.swiftinterface`.
- **`MarklyInlineText`** now detects images recursively (through strong/emphasis/strikethrough/link
  containers), so the common linked-image `[![alt](url)](link)` and `**![alt](url)**` patterns render
  the picture instead of just the alt text, and owns its base font so callers no longer apply a
  separate `.font`.

### Fixed

- Images no longer collapse to zero height (replaced the `AsyncImage` content-closure path with
  `MarklyRemoteImage`, which decodes to a platform image with an intrinsic size).
- A cancelled stale image fetch can no longer overwrite the correct image or clobber a successful
  load with the failure placeholder (generation-token guard).
- Images nested inside link/strong/emphasis/strikethrough inlines are no longer silently dropped.

## [0.3.1] - 2026-07-22

Follow-up to v0.3.0: test-framework migration, iOS 26 corner-radius polish, and the four
review-regression tests deferred from v0.3.0. 85 passing tests; builds clean on iOS, macOS,
tvOS, and visionOS 26.

### Changed

- **Migrated the entire test suite from XCTest to Swift Testing** (`import Testing`, `@Test`,
  `#expect` / `#require`, `@Suite struct`, `Issue.record`). XCTest is no longer used anywhere.
- **iOS 26 Liquid Glass corner radii**, applied per Apple's concentricity guidance rather than a
  single universal value: the large floating highlight toolbar uses 32pt, code blocks 20pt, and
  the small color-swatch chip stays 4pt; circles and capsules are untouched.

### Added

- Review-regression tests: chapter previous/next navigation (stops at edges, out-of-range no-op),
  settings-decode priority (`paperStyle` over legacy `theme`) and per-field fallback to defaults,
  controller theme resolution from the system color scheme + persistence, and inlineCode
  whitespace round-trip through the serializer (locks the selectable-text highlight coordinate basis).

## [0.3.0] - 2026-07-22

Initial public release. Apple-Books-style e-reader built on the sibling Nebula and Cosmos
packages. 76 passing tests; builds clean on iOS, macOS, tvOS, and visionOS 26.

### Added

- **Apple-Books-style toolbar chrome**: a top bar showing the current chapter title with an
  overflow menu (contents, search, bookmarks, highlights, appearance, previous/next chapter)
  and a bottom bar (contents, aA appearance, highlights, share), built from cross-platform
  primitives (`safeAreaInset` + `.primaryAction`) so it renders identically on iOS, macOS, and
  visionOS; tvOS reaches every feature through the overflow menu.
- **Free-form multi-color highlights**: select text to open an action bar with five marker
  colors + underline, a note editor, and remove. Highlights are scoped per book and persisted
  through a pluggable repository; the sticky color is remembered. Powered by a selectable text
  view (`UITextView` on iOS/iPadOS/visionOS, a self-sizing `NSTextView` on macOS, a `Text`
  fallback on tvOS).
- **Chapters**: top-level `#` headings become chapters (leading blocks form an implicit
  "Start of document" chapter; no-`#` documents are a single implicit chapter), with previous/
  next navigation.
- **Appearance (aA) sheet**: font size (discrete steps), brightness, paper style
  (auto / white / sepia / night / dark), and reading mode (scroll / pages), all persisted and
  restored on launch. Settings migrate a legacy v0.2 `theme` store into `paperStyle`.
- **Share** of the book title + opening excerpt (iOS / iPadOS / visionOS / macOS).
- Data model: `MarklyHighlight`, `MarklyHighlightColor`, `MarklyChapter` / `MarklyChapters`,
  `PaperStyle`, `MarklyFontSize`, a `MarklyHighlightRepository` seam, and four reader
  environment values wiring the controller's state into block views.

### Changed

- `Package.swift` dependencies switched from local path overrides to published git URLs
  (`byescaleira/nebula` from 0.18.0, `byescaleira/cosmos` from 0.2.0) so external consumers
  resolve without a local checkout.
- `MarklyReader` now wraps the reading surface in a `NavigationStack` and drives chrome,
  environment injection, the brightness dimmer, and sheet presentation.
- `MarklyReaderSheet` is now a three-tab Contents / Bookmarks / Highlights sheet.

### Fixed

- TOC current-section cue is no longer color-only: the active row carries an `.isSelected`
  accessibility trait + value so VoiceOver can identify it.
- The font-size and brightness sliders now expose `.accessibilityLabel` (the heading `Text`
  was a sibling, not the slider's label).
- The highlight Note flow now works on a fresh selection — previously the button was disabled
  until a color was applied and could save nothing; it now creates a highlight with the sticky
  color and attaches the note (regressed by `testCreateThenSetNoteProducesSingleHighlightWithNote`).

## [0.2.0]

Reader foundation (prior, unpublished milestone).

### Added

- Table of contents, reading-position persistence (one per book), and bookmarks.
- Reader settings (theme + reading mode) over NebulaPreferences, plus `.paged` reading mode.
- In-document search (pure, section-scoped, snippet-windowed, case/whole-word options,
  debounced + off-main).
- Nebula errors + instrumentation: layer errors as `NebulaFailure` bridging to closed
  `NebulaError.Kind`; opt-in `Markly.configure(subsystem:)`; the parse path is an
  `.instrumented()` NebulaUseCase.

## [0.1.0]

Core reader (prior, unpublished milestone).

### Added

- Pure block/inline domain model, swift-markdown parser, SwiftUI block renderers, and the
  `MarklyReader` entry point + `MarklyReaderController`.
- Passed an adversarial code review (5-dimension, refutation-verified; 22 findings, 20
  confirmed) — all confirmed defects fixed and locked in with regression tests.

[Unreleased]: https://github.com/byescaleira/markly/compare/0.4.0...HEAD
[0.4.0]: https://github.com/byescaleira/markly/releases/tag/0.4.0
[0.3.1]: https://github.com/byescaleira/markly/releases/tag/0.3.1
[0.3.0]: https://github.com/byescaleira/markly/releases/tag/0.3.0
[0.2.0]: https://github.com/byescaleira/markly/releases/tag/0.2.0
[0.1.0]: https://github.com/byescaleira/markly/releases/tag/0.1.0