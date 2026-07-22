# Markly — Architecture

Markly is a SwiftUI markdown **e-reader** shipped as a Swift Package. It renders markdown and provides reader functionality — table of contents, bookmarks, reading-position persistence, reader themes, Dynamic Type — and is designed to be **pluggable into any app with `import Markly` + a single `MarklyReader` view call**.

It is built on two sibling local packages:

- **Nebula** (`../nebula`) — Foundation-only Clean Architecture spine (`UseCase`, `Repository`, `Preferences`, `Errors`, `Logging`, …). No SwiftUI.
- **Cosmos** (`../cosmos`) — SwiftUI design system: atoms, theme tokens, and modifiers.

Markdown is parsed **exclusively** with Apple's official `apple/swift-markdown` (`Markdown` module, pinned `from: "0.8.0"`). Inline runs render through Foundation `AttributedString(markdown:options:)`. **No third-party markdown parser or renderer is permitted** — this package follows only Apple guidelines and Apple's official markdown documentation.

Deployment targets: **iOS / macOS / tvOS / visionOS 26.0**. **No watchOS** (long-form reader chrome needs a `ScrollView` + focusable-anchor surface that does not fit watchOS). Swift 6 language mode, `swift-tools-version: 6.3`.

> This document describes the **as-built** package. v0.1 + Phase 2 are covered inline; **§11 covers v0.3** (Apple Books-style toolbar chrome, selectable-text highlights, chapters, settings, share).

---

## 1. Package shape

- `swift-tools-version: 6.3`, `swiftLanguageModes: [.v6]` (Swift 6 strict concurrency).
- `defaultLocalization: "en"`; reader chrome strings live in `Resources/Localizable.xcstrings` (processed to `.lproj/.strings`, read via `Bundle.module`).
- Dependencies: Nebula + Cosmos as **local path** deps during development (switch to git versioned at publish time); `apple/swift-markdown` as a git versioned dep.
- Single product `Markly` → target `Markly` (deps: `Nebula`, `Cosmos`, `Markdown`). Test target `MarklyTests` with `Fixtures/` processed resources.

## 2. Layers

```
Public/        ← the host-facing API (MarklyReader, MarklyBook, MarklyConfiguration, …)
Reader/        ← the reading surface (ScrollView + LazyVStack)
Rendering/     ← per-block SwiftUI views (block, inline, list, table, code)
Domain/
  Parser/      ← swift-markdown Document → [MarklyBlock]
  BlockModel/  ← pure, Sendable, Codable block + inline model
Resources/     ← Localizable.xcstrings
```

The dependency direction is strictly **Public → Reader → Rendering → Domain**. `Domain` depends on nothing but `Markdown` + Foundation. This is the same separation Nebula enforces (entity/model knows nothing of UI) and keeps the block model unit-testable without SwiftUI.

## 3. Why Markly owns block layout

Apple provides **no** SwiftUI primitive that renders markdown *blocks* (headings, lists, tables, block quotes) as native views. Foundation `AttributedString(markdown:)` only handles **inline** markdown (bold, italic, links, code spans) — and only when configured `interpretedSyntax: .inlineOnlyPreservingWhitespace`. So Markly's division of labor is:

- **Inline** → Foundation `AttributedString(markdown:)` rendered through native `Text`. This is the only Apple-sanctioned inline renderer and it guarantees correct bold/italic/strikethrough/link/code semantics per Apple's markdown docs. `MarklyInlineText` serializes `MarklyInline` back to a markdown string (via `MarklyInlineSerializer`, which escapes `\ * _ ` [ ] !`) and hands it to `AttributedString(markdown:options:baseURL:)`.
- **Block** → SwiftUI views owned by Markly, styled from Cosmos theme tokens. Each block case in `MarklyBlockView` produces a view; headings carry `.accessibilityHeading(...)`, code blocks get a copy button + `.accessibilityTextContentType(.sourceCode)`, tables get a horizontally-scrollable grid with per-column alignment, block quotes get a leading bar, lists get markers with correct ordered start index, thematic breaks use `CosmosDivider`.

`CosmosText` exposes no `AttributedString` initializer, so inline runs must go through native `Text` — this is the pivotal constraint that forced the inline-vs-block split.

## 4. Public API surface (v0.1)

```swift
// One-call rendering:
MarklyReader(book: MarklyLiteralBook(title: "Demo", markdown: "# Hello"))

// Or with configuration / a programmatic handle:
let controller = MarklyReaderController(book: book, configuration: .init(theme: .sepia))
MarklyReader(book: book, controller: controller)
controller.setTheme(.dark)
```

- `MarklyReader: View` — the entry point. Wires the Cosmos environment (theme observable + `cosmosTheme`/`cosmosConfiguration` `@Entry` values + `.cosmosOpenURL(inApp:)`), parses the book's markdown in `.task`, and presents `MarklyReaderView`.
- `MarklyBook: Sendable, Identifiable where ID == UUID` — `var title: String; var author: String?; func source() async throws -> String`. `MarklyLiteralBook` is the built-in in-memory book; hosts conform their own for files/network.
- `MarklyConfiguration: Sendable` — `theme`, `readingMode` (`.continuous` / `.paged`), `features`, `openURLInApp: @Sendable (URL) -> Bool`. Deliberately **not** `Equatable` (closure). `.default` is light + continuous + all features + no in-app URLs.
- `MarklyFeatures` — `tableOfContents / search / bookmarks / share` flags with `.all` / `.none`.
- `MarklyReaderTheme` (`.light/.dark/.sepia/.night`) — maps to a `CosmosTheme` (sepia/night via `CosmosColorTokens.marklySepia/marklyNight`; light/dark reuse `CosmosTheme.default`).
- `MarklyReaderController` — `@MainActor @Observable` host handle: owns the live `CosmosThemeObservable`, exposes `currentSectionID`, `setTheme(_:)`. This mirrors Cosmos's own `CosmosThemeObservable` pattern (main-actor + `@Observable` is the Swift-6-safe way to drive view updates from a shared mutable theme).

## 5. Domain model

`MarklyBlock` (recursive `enum`, `Sendable`, `Equatable`, `Codable`): `heading(level:inlines:id:)`, `paragraph`, `codeBlock(language:code:)`, `blockQuote(blocks:)`, `list(ordered:start:items:)`, `thematicBreak`, `table(header:rows:)`, `htmlBlock(String,id:)`, `blockDirective(name:arguments:blocks:)`. Each case carries a `MarklySectionID` for TOC anchoring / scroll restoration.

`MarklyInline` (enum, Sendable, Equatable, Codable): `text`, `softBreak`, `lineBreak`, `strong`, `emphasis`, `strikethrough`, `inlineCode`, `link(destination:inlines:)`, `image(source:alt:)`.

`MarklySectionID` is a `Hashable, Sendable, Codable` wrapper around a `String`. IDs are **stable across runs** for headings (`slugify` of heading plain text, e.g. `h2-introduction`) and sequential (`blk-0042`) for non-heading blocks. Stability is what makes reading-position persistence and bookmarks reliable across launches.

`MarklyTableCell(inlines:alignment:)` + `MarklyColumnAlignment` (`.left/.right/.center`) back the table.

## 6. Parser

`MarklyDocumentParser.parse(_ source: String) -> [MarklyBlock]` (and `parse(_ document: Document)`) builds the model from a `Markdown.Document`. It switches on the concrete swift-markdown node types — **`OrderedList` / `UnorderedList`** (the `Markdown` module has no `List` type), `Heading`, `Paragraph`, `CodeBlock`, `BlockQuote`, `ThematicBreak`, `Table`, `HTMLBlock`, `BlockDirective` — and recurses via `InlineCollector` for inline children. Ordered lists use `Int(list.startIndex)` for the start number; list items may contain multiple child blocks (nested lists, paragraphs). Directive arguments are joined from `directive.argumentText.segments.map(\.untrimmedText)`.

Round-trip fidelity of inline serialization is exercised by the parser tests; `MarklyInlineSerializer.escape()` escapes the markdown-active characters `\ * _ ` [ ] !`.

## 7. Concurrency model

- `MarklyReaderController` is `@MainActor @Observable` — the main actor serializes theme/section mutation; `@Observable` drives SwiftUI updates. The controller is **not** `Sendable` (it's main-actor-isolated, which is the correct pattern).
- `MarklyConfiguration` is `Sendable`; its `openURLInApp` is `@Sendable (URL) -> Bool`.
- `MarklyBook`, `MarklyBlock`, `MarklyInline`, `MarklySectionID`, `MarklyReaderTheme`, `MarklyFeatures` are all `Sendable`.
- `MarklyReader.load()` is `@MainActor` and `await`s `book.source()`; parse is synchronous and cheap (CPU-bound, swift-markdown is fast).
- State (`blocks`, `loaded`, `controller`) is `@State`; the `@Observable` controller is injected via `@State` + `.environment(...)`.

## 8. Apple-guideline adherence

- **Parsing**: only `apple/swift-markdown`, Apple's official parser.
- **Inline rendering**: only Foundation `AttributedString(markdown:options:)` with `.inlineOnlyPreservingWhitespace` + `.returnPartiallyParsedIfPossible`.
- **Accessibility**: headings → `.accessibilityHeading(.h1…h6)`; code blocks → `.accessibilityTextContentType(.sourceCode)`; block-quote bar via `Rectangle().fill(theme.colors.outline)` (no custom drawing). Dynamic Type flows automatically because all typography comes from `theme.typography.font(for: CosmosTextStyle)`.
- **Reading surface**: `ScrollView` + `LazyVStack` + `.scrollTargetLayout()`. Continuous mode scrolls freely; `.paged` mode attaches `.scrollTargetBehavior(.paging)` (one screen-height page at a time). `ScrollViewReader` consumes the controller's `ScrollRequest` (TOC / bookmark jumps).
- **Platform parity**: pasteboard copy uses `#if os(macOS) NSPasteboard` / `UIKit UIPasteboard`; no API is used that is unavailable on any of iOS/macOS/tvOS/visionOS 26.
- **Errors / logging**: only Nebula's `NebulaError`/`NebulaFailure`/`NebulaErrorConfiguration`/`NebulaLogConfig` (themselves Foundation + `os.Logger` facades); layer errors are open structs bridging to the closed `NebulaError.Kind` (no new `Kind` cases). Search is pure Foundation (no third-party indexing). Recovery verbs (`RecoveryAction`) are value-based; the reader localizes the common verbs via `Bundle.module` and never reads developer-English `description` to users.

## 9. Known limitations / Phase 2

v0.1 passed an adversarial code review (5-dimension, refutation-verified; 22 findings, 20 confirmed). All confirmed correctness/accessibility/pluggability defects were fixed and locked in with regression tests (12 passing). Notable fixes: duplicate-heading `SectionID` de-duplication (`h2-x` → `h2-x-2`), block-directive parsing enabled (`ParseOptions.parseBlockDirectives`), code-language is the CommonMark first info-string token, `~` escaped in inline serialization (literal tildes no longer become strikethrough), link/image destinations angle-wrapped when unsafe (`)`/`(`/whitespace), images render via `CosmosAsyncImage` (not alt text), book swaps reload via `.task(id: book.id)`, parsing runs off the main actor, load failure / empty book surface a localized state instead of a blank page, code blocks and tables scroll horizontally (`fixedSize`/`Grid`), table header cells carry `.isHeader`, list items combine for VoiceOver, layout metrics scale with Dynamic Type (`@ScaledMetric`), the host's `cosmosConfiguration` is no longer force-overridden, the Copy button is hidden on tvOS (no pasteboard), and reader chrome is localized via `Bundle.module`.

Remaining limitations:
- **No runtime verification**: there is no host app and SwiftUI `#Preview` cannot run headlessly; correctness is verified by compile (macOS host) + parser unit tests only. tvOS/iOS/visionOS compile-correctness of platform gates is reasoned, not built (no cross-SDK `swift build` without a host app).
- HTML blocks render as verbatim preformatted text (Apple-only: no inline HTML rendering).
- **Phase 2 — shipped**: TOC (`MarklyTOC` + `MarklyTOCView`, headings recursively collected incl. inside block-quotes/lists/directives), reading-position persistence (one `MarklyReadingPosition` per book, keyed by `book.id`; debounced auto-save + onDisappear final save + restore-on-load scroll), bookmarks (`MarklyBookmark` + `MarklyBookmarksView`, scoped per book, context-menu delete), reader settings (`MarklyReaderSettings` + `MarklyReaderSettingsStore` over `NebulaPreferences`; theme + reading mode persisted and restored on launch, overriding seeded configuration), `.paged` mode (`.scrollTargetBehavior(.paging)`), a two-tab Contents/Bookmarks sheet (`MarklyReaderSheet`).
- **Phase 2 — shipped (Track 3)**: in-document search (`MarklySearch` + `MarklySearchView`; pure, per-occurrence, section-scoped, snippet-windowed, case/whole-word options; debounced + off-main; `MarklyFeatures.search`-gated sheet), Nebula errors + instrumentation (layer errors `MarklySourceError`/`MarklyParseError`/`MarklyRenderError` as `NebulaFailure` open structs bridging to the closed `NebulaError.Kind` with `metadata["MarklyCode"]`; `Markly.configure(subsystem:)` opt-in installs `NebulaErrorConfig`/`NebulaLogConfig` with a per-`MarklyCode` `NebulaUserError` map; the parse path is a `.instrumented()` `NebulaUseCase` — `reported().measured().logged()`; load failures report + log + resolve recovery actions). 57 passing tests (12 parser + 10 reading/settings + 17 search + 11 error-mapping + 7 instrumentation).
- **Remaining backlog**: tvOS focusable anchors, DocC catalog, fuller Cosmos-atom chrome (CosmosButton/CosmosList/CosmosSection/CosmosMenu + `CosmosTextField` replacing the native SwiftUI chrome used in v0.1), localized recovery-action dispatch / modal error presentation. *(Typography-scaling settings shipped in v0.3 — see §10.)*

## 10. v0.3 — Apple Books-style chrome, highlights, chapters, settings, share

v0.3 turns the reader into an Apple-Books-style e-reader: top + bottom toolbars with menus, free-form multi-color highlights, chapters derived from `#` headings, an appearance (aA) sheet, and share. All four platforms (iOS/macOS/tvOS/visionOS) build and the test suite is **85 passing** (61 + 24 v0.3 domain tests in `MarklyV03DomainTests`, incl. regressions for the note-on-fresh-selection flow). The suite uses Apple's Swift Testing (`import Testing`, `@Test`, `#expect`/`#require`, `@Suite struct`) — XCTest was removed in v0.3.1.

### 10.1 Highlights via a selectable text view

SwiftUI `Text` cannot expose a text-selection **range** (`.textSelection(.enabled)` only copies), so free-form highlights need a real text view. `MarklySelectableText` (Rendering) is a `View` that picks the platform primitive:

- **iOS / iPadOS / visionOS** — `UIViewRepresentable` over a non-editable, selectable `UITextView` (`isScrollEnabled = false` so it sizes to content).
- **macOS** — `NSViewRepresentable` over a self-sizing `NSTextView` hosted in a custom `NSView` (`MarklySelectableTextHostView`) that overrides `intrinsicContentSize` from `layoutManager.usedRect(for:)` and re-layouts in `layout()`. `NSTextView` does not self-size the way `UITextView` does, and AppKit has **no** `NSFontMetrics`/`NSTraitCollection`/`NSContentSizeCategory`, so font scaling uses a linear factor.
- **tvOS** — no text selection exists, so paragraphs fall back to the non-selectable `MarklyInlineText` (`Text`) path. Highlights remain view-only there (the list + excerpts).

Formatting is built with `NSAttributedString(markdown:options:baseURL:)` (the UIKit/AppKit-native counterpart of `AttributedString(markdown:)`), so bold/italic/strikethrough/code render correctly in the text view. **On both UIKit and AppKit the options type is `AttributedString.MarkdownParsingOptions`** — the ObjC `NSAttributedStringMarkdownParsingOptions` class is `NS_REFINED_FOR_SWIFT` and does not surface as `NSAttributedString.MarkdownParsingOptions` in Swift. Fonts are re-scaled per run via `fontDescriptor.withSize(_:)` (preserving bold/italic symbolic traits) to `MarklyFontSize.scale *` the body point size. Existing highlights are applied as attributed-string attributes — `.backgroundColor` (color cases) or `.underlineStyle`+`.underlineColor` (the underline case) — over their stored character ranges. The user's selection is observed via `UITextViewDelegate.textViewDidChangeSelection` / `NSTextViewDelegate.textViewDidChangeSelection` and reported as a `Range<Int>` (character offsets), or `nil` when cleared.

**Range-coordinate basis.** The text view's string is the re-parsed markdown of the block's inlines (via `MarklyInlineSerializer.toMarkdown` + `AttributedString.MarkdownParsingOptions(.inlineOnlyPreservingWhitespace)`). Selection → create → re-render all use this **same** basis, so a stored highlight re-renders at the correct offset. (The Highlights-list excerpt uses `inlinePlainText(inlines)`; the two plain texts agree for all inline kinds except line-break/whitespace edge cases, where the excerpt is cosmetic-only.)

`MarklyBlockView.paragraph` routes through `MarklySelectableText` when `features.highlights` is on and the paragraph holds no inline image (images can't live in a text view), gated `#if !os(tvOS)`. Four environment values (`marklyReaderFeatures`, `marklyReaderFontSize`, `marklyHighlightsProvider`, `marklySelectionObserver` — in `MarklyReaderEnvironment`) inject the controller's state into the leaf block view without coupling it to the controller.

### 10.2 Chrome (top + bottom toolbars)

`MarklyReader` wraps the reading surface in a `NavigationStack` and builds:

- **Top bar** — `.navigationTitle` shows the current chapter title (or the book title when there is no current chapter) via `controller.principalTitle(for:)`; `.toolbarTitleDisplayMode(.inline)`. A single `.primaryAction` `ToolbarItem` holds the overflow `⋯` `Menu` (contents, search, bookmarks, highlights, appearance, and — when chapters exist — previous/next chapter). `.primaryAction` is the one toolbar placement available on every platform; `.topBarTrailing`/`.bottomBar`/`.navigationBar` are **iOS-only** and are avoided.
- **Bottom bar** — a `safeAreaInset(edge: .bottom)` bar (Contents / aA / Highlights / Share) rather than a `.bottomBar` toolbar placement, so it renders identically on iOS, macOS, and visionOS. tvOS has no bottom bar and reaches every feature through the overflow menu.

A brightness dimmer (`Color.black.opacity(1 - brightness)`, non-interactive, `accessibilityHidden`) overlays the reader on every platform except tvOS (which manages brightness at the system level).

### 10.3 Highlights action bar + list

`MarklyHighlightToolbar` is a floating bar shown above the bottom bar while a text selection is active (`pendingSelection` in `MarklyReader`). It offers the five marker colors + underline (tap creates a highlight with that color — which becomes the sticky color — or recolors an existing highlight covering the exact range), a note editor (`CosmosTextField`, sheet), and delete. The Highlights list (`MarklyHighlightsView`) shows each highlight's excerpt + color swatch + note, with tap-to-jump and context-menu delete; it is the third tab of `MarklyReaderSheet` (Contents / Bookmarks / Highlights).

### 10.4 Appearance (aA) sheet

`MarklySettingsSheet` (presented from the bottom-bar aA button or the overflow menu) exposes font size, brightness, paper style, and reading mode, each pushed straight through `MarklyReaderController` (which persists it and, for paper style, re-resolves the live theme):

- **Font size** — an Apple-Books-style small-A / large-A `Slider` over the discrete steps (index ↔ `MarklyFontSize`). `Slider` (and `Stepper`) are unavailable on tvOS, so there a `Picker` over the steps is used instead.
- **Brightness** — a `Slider` (omitted on tvOS).
- **Paper style** — a segmented `Picker` (Auto / White / Sepia / Night / Dark); `.auto` follows the system appearance, re-resolved live via `.onChange(of: colorScheme)`.
- **Reading mode** — a segmented `Picker` (Scroll / Pages).

### 10.5 Chapters

`MarklyChapters` derives chapters from top-level `#` headings: each `#` starts a chapter spanning until the next `#`; blocks before the first `#` form an implicit "Start of document" chapter; a document with no `#` is a single implicit chapter. `indexMap(from:)` recurses into block quotes / list items / block directives so a `currentSectionID` belonging to a nested block still resolves to its enclosing chapter. The reader sets chapters + the index map on load and shows the current chapter title in the top bar; previous/next chapter live in the overflow menu.

### 10.6 Data model + persistence additions

- `MarklyHighlight` (`NebulaEntity`, `Codable`, `Sendable`) — `bookID`, `sectionID`, `range: Range<Int>`, `color: MarklyHighlightColor`, `note: String?`, `createdAt`.
- `MarklyHighlightColor` (`Int` raw values: underline=0, green=1, blue=2, yellow=3, pink=4, purple=5; `markerColors` excludes underline) with SwiftUI color resolution in `MarklyAppearance+SwiftUI`.
- `PaperStyle` (auto/white/sepia/night/dark) + `MarklyFontSize` (7 steps, `.default` = `.large`, `nextLarger`/`nextSmaller`, `stepLabel`, `scale`).
- `MarklyReaderSettings` now holds `readingMode` / `paperStyle` / `fontSize` / `brightness` / `lastHighlightColor`; its custom `Codable` **migrates** a legacy v0.2 store that persisted only `theme` + `readingMode` into `paperStyle` (via `PaperStyle.from(theme:)`).
- `MarklyHighlightRepository` protocol + `MarklyPreferencesRepository`/`NebulaFakeRepository` conformances; `MarklyDefaultRepositories.highlightRepository()`. The controller loads highlights scoped by `book.id`, and the sticky `lastHighlightColor` is updated on both create and recolor.

### 10.7 v0.3 platform notes

- `.bottomBar` / `.topBarTrailing` / `.navigationBar` toolbar placements are iOS-only → the bottom bar uses `safeAreaInset`; the overflow uses `.primaryAction`.
- `Slider` and `Stepper` are unavailable on tvOS → font size uses a `Picker` there; brightness is omitted.
- `.textFieldStyle(.roundedBorder)` is unavailable on tvOS → gated in `MarklySearchView`.
- Text selection (and thus highlight creation) exists on iOS/iPadOS/visionOS/macOS only; tvOS keeps the `Text` paragraph path and reaches features through the overflow menu.

## 11. File inventory

```
Sources/Markly/
  Markly.swift                          version constant
  Domain/BlockModel/
    MarklyBlock.swift                   recursive block enum
    MarklyInline.swift                  inline enum
    MarklySectionID.swift               stable section identifier
    MarklyTableCell.swift               table cell + column alignment
  Domain/Parser/
    MarklyDocumentParser.swift          Markdown.Document → [MarklyBlock]
    MarklyInlineSerializer.swift        [MarklyInline] → markdown string
    MarklyParseUseCase.swift            parse as .instrumented() NebulaUseCase + DTOs
  Domain/Errors/
    MarklyErrors.swift                  MarklySourceError/Parse/Render (NebulaFailure)
  Domain/Search/
    MarklySearch.swift                  pure in-document search + result/options
  Domain/Reading/
    MarklyReadingPosition.swift         one-position-per-book entity
    MarklyBookmark.swift                bookmark entity
    MarklyReadingRepositories.swift     Nebula repository seams + prefs-backed store
  Domain/TOC/
    MarklyTOC.swift                     heading → TOC entry derivation
  Domain/Highlights/
    MarklyHighlight.swift               highlight entity (range = char offsets)
    MarklyHighlightColor.swift          underline/green/blue/yellow/pink/purple
    MarklyHighlightRepository.swift     Nebula repository seam for highlights
  Domain/Chapters/
    MarklyChapter.swift                 chapter entity + chapters-by-sections builder
  Rendering/
    MarklyBlockView.swift               per-block switch (routes paragraphs → selectable text)
    MarklyInlineText.swift              inline → AttributedString → Text
    MarklySelectableText.swift          UITextView/NSTextView selectable-text highlight surface (v0.3)
    MarklyCodeBlockView.swift            code block + copy button
    MarklyListView.swift                ordered/unordered list markers
    MarklyTableView.swift               aligned, scrollable table grid
  Reader/
    MarklyReaderView.swift              ScrollView + LazyVStack surface (continuous/paged)
    MarklyReaderEnvironment.swift       features/fontSize/highlights/selection env values (v0.3)
    MarklyTOCView.swift                 TOC list
    MarklyBookmarksView.swift           bookmark list
    MarklyHighlightsView.swift          highlights list (color swatch + note + jump/delete) (v0.3)
    MarklyHighlightToolbar.swift        selection-action bar (colors/note/remove) (v0.3)
    MarklySettingsSheet.swift           aA appearance sheet (font/brightness/paper/mode) (v0.3)
    MarklyReaderSheet.swift             Contents/Bookmarks/Highlights sheet (3 tabs)
    MarklySearchView.swift              search field + debounced results sheet
  Public/
    Markly.swift                        namespace + version
    MarklyReader.swift                  entry point (#Preview lives here)
    MarklyBook.swift                    book protocol + literal impl
    MarklyConfiguration.swift           config + reading mode + features
    MarklyReaderTheme.swift             reader themes → CosmosTheme
    MarklyReaderController.swift        @MainActor @Observable host handle
    MarklyReaderSettings.swift          persisted reader settings + store (migrates v0.2 theme→paperStyle)
    MarklyPaperStyle.swift              PaperStyle + MarklyFontSize enums (v0.3)
    MarklyAppearance+SwiftUI.swift      color/font-size → SwiftUI values (v0.3)
    MarklyErrorConfig.swift             Markly.configure() + default error/log configs
  Previews/
    MarklyPreviews.swift                exhaustive #Preview set (every component + reader surface)
  Resources/
    Localizable.xcstrings               reader chrome string catalog
Sources/MarklyTests/
  MarklyDocumentParserTests.swift       16 parser tests (incl. inlineCode whitespace round-trip)
  MarklyReadingTests.swift              10 reading/settings tests
  MarklySearchTests.swift               17 search tests
  MarklyErrorMappingTests.swift         11 error-bridge tests
  MarklyInstrumentationTests.swift      7 use-case/report tests
  MarklyV03DomainTests.swift            24 v0.3 domain tests (highlights/chapters/paper/font + note-flow regressions + chapter navigation, settings-decode priority/fallback, theme resolution) (v0.3)
  Fixtures/sample.md                    all-blocks fixture
```

**Total: 85 passing tests** (61 v0.1/v0.2 + 24 v0.3), all on Apple's Swift Testing (`import Testing`, `@Test`, `#expect`/`#require`, `@Suite struct`) — XCTest was removed in v0.3.1.

**v0.3.1 follow-up**: migrated the entire suite from XCTest to Swift Testing; applied iOS 26 Liquid Glass corner radii per Apple's concentricity guidance (the large floating highlight toolbar uses 32pt, code blocks 20pt, the small color swatch chip stays 4pt; circles/capsules are untouched); and added the four review-regression tests deferred from v0.3 (chapter navigation, settings-decode priority/fallback, controller theme resolution, inlineCode whitespace round-trip).

v0.3 passed an adversarial code review (multi-dimension, refutation-verified). Four findings were confirmed and fixed: the TOC current-section row now carries an `.isSelected` accessibility trait + value (the accent-color cue was color-only); the font-size and brightness sliders gained `.accessibilityLabel` (the heading `Text` was a sibling, not the slider's label); the Note flow now works on a fresh selection (it was disabled until a color was applied, then could save nothing — it now creates a highlight with the sticky color and attaches the note, locked in by `testCreateThenSetNoteProducesSingleHighlightWithNote`); and an empty note on a fresh selection is a no-op (`testSetNoteNilClearsExistingNote`). One deferred finding: the highlight action bar floats at the viewport bottom rather than anchored above the selection rect as Apple Books does — anchoring requires plumbing the text view's selection geometry across platforms and is tracked as backlog.