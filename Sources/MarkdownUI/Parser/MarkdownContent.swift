//
//  MarkdownContent.swift
//  MarkdownUI
//
//  Vendored from gonzalezreal/swift-markdown-ui (MIT; Copyright (c) 2020 Guillermo Gonzalez).
//  Trimmed for Markly: the cmark-backed `init(_ markdown: String)` and the result-builder
//  `init(@MarkdownContentBuilder:)` were removed (Markly drives rendering from its own
//  apple/swift-markdown parse via `MarklyBlock → BlockNode` converters, so the cmark parser and
//  the programmatic DSL are not vendored). The `renderMarkdown`/`renderHTML` methods were removed
//  (they depended on cmark-backed `Sequence<BlockNode>` extensions not vendored here). What
//  remains is the content container `BlockConfiguration.content` / `TableCellConfiguration.content`
//  require: a value holding a `[BlockNode]` tree.
//

import Foundation

/// A Markdown content value: a sequence of blocks (structural elements like paragraphs,
/// blockquotes, lists, headings, thematic breaks, code blocks).
///
/// Vendored from gonzalezreal/swift-markdown-ui and trimmed for Markly (see file header).
public struct MarkdownContent: Equatable {
  /// Returns a Markdown content value with the sum of the contents of all the container blocks
  /// present in this content (the children of blockquotes/lists). Returns `nil` if there are none.
  public var childContent: MarkdownContent? {
    let children = self.blocks.map(\.children).flatMap { $0 }
    return children.isEmpty ? nil : .init(blocks: children)
  }

  /// The block tree (internal: `BlockNode` is not public).
  let blocks: [BlockNode]

  /// Creates a Markdown content value from a block tree.
  init(blocks: [BlockNode] = []) {
    self.blocks = blocks
  }

  /// Creates a Markdown content value from a single block.
  init(block: BlockNode) {
    self.init(blocks: [block])
  }
}