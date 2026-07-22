//
//  MarklyChapter.swift
//  Markly
//
//  Chapter derivation: groups a book's blocks into chapters keyed by top-level `#` (H1) headings.
//  A chapter spans from its H1 until the next H1 (or the end of the document); blocks before the
//  first H1 form an implicit "Start of document" chapter. If the book has no H1 headings at all, a
//  single implicit chapter spans the whole book. Chapters are derived in memory from the parsed
//  block model (no persistence) — the table-of-contents view renders chapters as the top tier and
//  nested sub-headings (##, ###, …) as the second tier, and the reader shows the current chapter
//  title in the principal toolbar item. See docs/Architecture.md §5.
//

import Foundation

/// A chapter: a top-level (`#`) heading and every block that belongs to it.
public struct MarklyChapter: Sendable, Equatable, Identifiable {
    /// The chapter's id — the H1's `MarklySectionID`, or a synthetic id for the implicit
    /// leading/only chapter.
    public let id: MarklySectionID
    /// The chapter's plain-text title (the H1's flattened inlines, or "Start of document").
    public let title: String
    /// `true` for the implicit leading/whole-book chapter (rendered without a chapter glyph).
    public let isImplicit: Bool
    /// The section id of the chapter's first block — the scroll target for "go to chapter".
    public let firstBlockID: MarklySectionID
    /// The ids of every block in the chapter, in document order (used to detect the current
    /// chapter from the reader's `currentSectionID`).
    public let blockIDs: [MarklySectionID]

    /// Creates a chapter.
    public init(
        id: MarklySectionID,
        title: String,
        isImplicit: Bool,
        firstBlockID: MarklySectionID,
        blockIDs: [MarklySectionID]
    ) {
        self.id = id
        self.title = title
        self.isImplicit = isImplicit
        self.firstBlockID = firstBlockID
        self.blockIDs = blockIDs
    }
}

/// Derives chapters from parsed blocks.
public enum MarklyChapters {
    /// The title used for the implicit leading chapter (blocks before the first `#`), matching
    /// `MarklySearch.startOfDocumentTitle`.
    public static let startOfDocumentTitle = "Start of document"

    /// Extracts chapters from the given blocks. Each top-level (`#`) heading starts a chapter that
    /// spans until the next `#`. Blocks before the first `#` form an implicit "Start of document"
    /// chapter. If there are no `#` headings at all, a single implicit chapter spans the whole
    /// book. Only top-level blocks are considered (chapters do not recurse into block quotes or
    /// list items, since those are content within a chapter).
    public static func entries(from blocks: [MarklyBlock]) -> [MarklyChapter] {
        guard !blocks.isEmpty else { return [] }

        var chapters: [MarklyChapter] = []
        var currentTitle: String? = nil
        var currentImplicit = false
        var currentFirst: MarklySectionID? = nil
        var currentIDs: [MarklySectionID] = []

        func flush() {
            guard let first = currentFirst else { return }
            let title = currentTitle ?? startOfDocumentTitle
            // The chapter's id is its first block's section id (the H1 for a titled chapter, the
            // first leading block for the implicit "Start of document" chapter).
            let id = currentIDs.first ?? MarklySectionID(raw: "chapter-start")
            chapters.append(
                MarklyChapter(
                    id: id,
                    title: title,
                    isImplicit: currentImplicit,
                    firstBlockID: first,
                    blockIDs: currentIDs
                )
            )
            currentTitle = nil
            currentImplicit = false
            currentFirst = nil
            currentIDs = []
        }

        for block in blocks {
            if case let .heading(level, inlines, id) = block, level == 1 {
                // A top-level heading starts a new chapter: flush the previous one first.
                flush()
                currentTitle = inlinePlainText(inlines)
                currentImplicit = false
                currentFirst = id
                currentIDs = [id]
            } else {
                if currentFirst == nil {
                    // Leading blocks before any H1 → implicit chapter.
                    currentImplicit = true
                    currentFirst = block.id
                }
                currentIDs.append(block.id)
            }
        }
        flush()
        return chapters
    }

    /// Returns the index of the chapter containing the given section id, or `nil` if it is not in
    /// any chapter (e.g. the id belongs to a nested block inside a list/block-quote that the
    /// chapter grouping did not enumerate — those fall back to the enclosing chapter by order).
    public static func chapterIndex(for sectionID: MarklySectionID, in chapters: [MarklyChapter]) -> Int? {
        chapters.firstIndex { $0.blockIDs.contains(sectionID) }
    }

    /// Builds a map from every block's section id (recursing into block quotes, list items, and
    /// block directives) to its chapter index, using the same H1-boundary rule as `entries(from:)`.
    /// The index is 0-based in document order (leading blocks before the first `#` are index 0).
    /// This lets the reader resolve the current chapter from a `currentSectionID` that may belong
    /// to a nested block.
    public static func indexMap(from blocks: [MarklyBlock]) -> [MarklySectionID: Int] {
        var map: [MarklySectionID: Int] = [:]
        var index = -1
        // Assigns a block and every nested block (inside block quotes/lists/directives) to the same
        // chapter index — nested headings do NOT split chapters (only top-level `#` does, matching
        // `entries(from:)`).
        func assignNested(_ block: MarklyBlock, chapter: Int) {
            map[block.id] = chapter
            switch block {
            case .blockQuote(let inner, _):
                for sub in inner { assignNested(sub, chapter: chapter) }
            case .list(_, _, let items, _):
                for itemBlocks in items { for sub in itemBlocks { assignNested(sub, chapter: chapter) } }
            case .blockDirective(_, _, let inner, _):
                for sub in inner { assignNested(sub, chapter: chapter) }
            default:
                break
            }
        }
        for block in blocks {
            if case let .heading(level, _, _) = block, level == 1 {
                index += 1
            } else if index == -1 {
                // Leading blocks before any H1 belong to the implicit leading chapter (index 0).
                index = 0
            }
            assignNested(block, chapter: max(index, 0))
        }
        return map
    }
}