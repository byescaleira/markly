# Changelog

All notable changes to Markly are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to
[Semantic Versioning](https://semver.org) (relaxed pre-1.0 form).

## [Unreleased]

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

[Unreleased]: https://github.com/byescaleira/markly/compare/0.3.0...HEAD
[0.3.0]: https://github.com/byescaleira/markly/releases/tag/0.3.0
[0.2.0]: https://github.com/byescaleira/markly/releases/tag/0.2.0
[0.1.0]: https://github.com/byescaleira/markly/releases/tag/0.1.0