//
//  MarklyPreviews.swift
//  Markly
//
//  Exhaustive Xcode previews exercising every renderable component AND every reader feature
//  surface, so opening this package in Xcode shows the whole library at a glance:
//
//  - "All Components"        — one document rendering every block + inline type (the v0.1
//                              `#Preview` in MarklyReader.swift covers only a subset).
//  - "Theme — Sepia/Night/Dark" — each reader theme (Light is the All-Components preview).
//  - "Paged mode"            — `.scrollTargetBehavior(.paging)`.
//  - "Load failure"          — a `MarklyBook` whose `source()` throws → the error surface.
//  - "Empty book"            — empty source → the empty state.
//  - "Table of contents"     — `MarklyReaderSheet` (Contents + Bookmarks tabs).
//  - "Search"                — `MarklySearchView` (field + results surface).
//
//  Like the existing preview, these are unguarded (they compile under `swift build`); they do
//  NOT mutate process-wide `NebulaErrorConfig`/`NebulaLogConfig`, so they stay side-effect-free
//  (the recovery-action map is exercised in `MarklyErrorMappingTests`, not in previews).
//

import SwiftUI

// MARK: - Shared sampler document

/// A markdown string that exercises every block and inline type Markly can render.
private let samplerMarkdown: String = """
# The Markly Sampler

> A complete tour of every block and inline Markly can render.

This paragraph has **bold**, *italic*, ~~strikethrough~~, `inline code`, and a [link](https://example.com). It also carries an image:

![Markly banner](https://placehold.co/600x160/EEEEEE/333333?text=Markly)

A linked image — `[![alt](url)](link)` — renders the picture, not just the alt text:

[![Markly on GitHub](https://placehold.co/480x120/333333/FFFFFF?text=Markly)](https://github.com/byescaleira/markly)

\(hardBreakDemo)

A soft break
across two lines (renders as a space).

## Inline styles

- **Strong**, *emphasis*, and ~~strikethrough~~
- `inline code` and [a link](https://example.com)
- An inline image: ![img](https://placehold.co/120x120/333333/FFFFFF?text=img)

## Lists

### Ordered

1. First
2. Second
   - Nested unordered
   - Another nested item
3. Third

### Unordered

- Apple
  - Honeycrisp
    - A third nesting level cycles the marker to a square
  - Gala
- Banana
  1. Nested ordered one
  2. Nested ordered two
- Cherry
- ![img](https://placehold.co/120x80/333333/FFFFFF?text=lead) An item leading with an image

## Code `blocks`

A fenced block with a language info string:

```swift
// A long line to demonstrate horizontal scrolling inside the code block view:
struct MarklyReader: View { let book: MarklyBook; var body: some View { Text(book.title) } }
```

A fenced block without a language:

```
plain code
across two lines
```

## Block quotes

> A block quote with **bold** and *italics*.
>
> A second paragraph inside the quote.
>
> > A nested block quote.

## Tables

| Left | Center | Right |
|:-----|:------:|------:|
| a    | b      | c     |
| 1    | 2      | 3     |
| α    | β      | γ     |

## Block directives

@note {
This is a **note** admonition — a swift-markdown block directive.
}

@warning {
Block directives can contain multiple paragraphs and **formatted** text.
}

## HTML

<details>
<summary>Raw HTML block</summary>
Renders as verbatim preformatted text (Apple-only: no inline HTML rendering).
</details>

## Thematic breaks

---

That is every component.
"""

/// A paragraph with a hard line break (two trailing spaces + newline), built separately because
/// trailing whitespace is fragile inside a multi-line string literal.
private let hardBreakDemo = "A line ending with two trailing spaces  \nforces a hard line break."

/// The parsed sampler blocks (shared by the reader, search, and TOC previews).
private let samplerBlocks: [MarklyBlock] = MarklyDocumentParser.parse(samplerMarkdown)

/// The sampler's table-of-contents entries.
private let samplerTOC: [MarklyTOCEntry] = MarklyTOC.entries(from: samplerBlocks)

/// A couple of seeded bookmarks for the TOC-sheet preview.
private let previewBookmarks: [MarklyBookmark] = {
    let bookID = UUID()
    let first = samplerTOC.first
    let second = samplerTOC.dropFirst().first
    return [
        MarklyBookmark(
            bookID: bookID,
            sectionID: first?.id ?? MarklySectionID(raw: "h1"),
            title: first?.title ?? "Bookmark"
        ),
        MarklyBookmark(
            bookID: bookID,
            sectionID: second?.id ?? MarklySectionID(raw: "h2"),
            title: second?.title ?? "Bookmark"
        ),
    ]
}()

/// A few seeded highlights for the sheet's Highlights-tab preview.
private let previewHighlights: [MarklyHighlight] = {
    let bookID = UUID()
    let first = samplerTOC.first
    return [
        MarklyHighlight(
            bookID: bookID, sectionID: first?.id ?? MarklySectionID(raw: "h1"),
            range: 0..<6, color: .yellow, note: nil
        ),
        MarklyHighlight(
            bookID: bookID, sectionID: first?.id ?? MarklySectionID(raw: "h1"),
            range: 8..<14, color: .green, note: "A note about this passage."
        ),
        MarklyHighlight(
            bookID: bookID, sectionID: first?.id ?? MarklySectionID(raw: "h1"),
            range: 20..<28, color: .underline, note: nil
        ),
    ]
}()

// MARK: - All components (the comprehensive preview)

#Preview("All Components") {
    MarklyReader(
        book: MarklyLiteralBook(title: "Markly Sampler", markdown: samplerMarkdown, author: "Markly"),
        configuration: .default
    )
}

// MARK: - Themes

#Preview("Theme — Sepia") {
    MarklyReader(
        book: MarklyLiteralBook(title: "Sepia", markdown: "# Sepia theme\n\nA warm palette for long-form reading."),
        configuration: MarklyConfiguration(theme: .sepia)
    )
}

#Preview("Theme — Night") {
    MarklyReader(
        book: MarklyLiteralBook(title: "Night", markdown: "# Night theme\n\nA high-contrast dark palette."),
        configuration: MarklyConfiguration(theme: .night)
    )
}

#Preview("Theme — Dark") {
    MarklyReader(
        book: MarklyLiteralBook(title: "Dark", markdown: "# Dark theme\n\nSystem-adaptive dark tokens."),
        configuration: MarklyConfiguration(theme: .dark)
    )
}

// MARK: - Paged mode

#Preview("Paged mode") {
    MarklyReader(
        book: MarklyLiteralBook(title: "Paged", markdown: samplerMarkdown),
        configuration: MarklyConfiguration(readingMode: .paged)
    )
}

// MARK: - Failure / empty states

#Preview("Load failure") {
    MarklyReader(book: FailingPreviewBook(), configuration: .default)
}

#Preview("Empty book") {
    MarklyReader(
        book: MarklyLiteralBook(title: "Empty", markdown: ""),
        configuration: .default
    )
}

// MARK: - Reader sheet (Contents + Bookmarks + Highlights)

#Preview("Table of contents") {
    MarklyReaderSheet(
        entries: samplerTOC,
        bookmarks: previewBookmarks,
        highlights: previewHighlights,
        highlightExcerpt: { highlight in
            "Highlight over range \(highlight.range.lowerBound)…\(highlight.range.upperBound)"
        },
        currentID: samplerTOC.first?.id,
        onSelectSection: { _ in },
        onDeleteBookmark: { _ in },
        onDeleteHighlight: { _ in }
    )
}

// MARK: - Appearance (aA) settings sheet

#Preview("Appearance settings") {
    MarklySettingsSheet(
        controller: MarklyReaderController(
            book: MarklyLiteralBook(title: "Sampler", markdown: "# Sampler")
        ),
        colorScheme: .light
    )
}

// MARK: - Search

#Preview("Search") {
    MarklySearchView(blocks: samplerBlocks) { _ in }
}

// MARK: - Preview-only failing book

/// A `MarklyBook` whose `source()` always throws, so the reader's load-failure surface renders.
private struct FailingPreviewBook: MarklyBook {
    let id = UUID()
    let title = "Unavailable Book"
    let author: String? = nil

    func source() async throws -> String {
        throw MarklyPreviewError()
    }
}

/// A trivial error thrown by `FailingPreviewBook`.
private struct MarklyPreviewError: Error {}
