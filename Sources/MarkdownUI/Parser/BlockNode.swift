//
//  BlockNode.swift
//  MarkdownUI
//
//  Vendored from gonzalezreal/swift-markdown-ui (MIT; Copyright (c) 2020 Guillermo Gonzalez).
//  Access levels raised to `public` (with public memberwise inits) so Markly — a separate module
//  that does NOT vendor the cmark-based `MarkdownParser` — can construct `BlockNode` trees from its
//  own `MarklyBlock` AST and render them via `BlockNode: View`. Upstream kept these internal
//  because its own `MarkdownParser` was the only constructor; Markly needs to be its own.
//

import Foundation

public enum BlockNode: Hashable {
  case blockquote(children: [BlockNode])
  case bulletedList(isTight: Bool, items: [RawListItem])
  case numberedList(isTight: Bool, start: Int, items: [RawListItem])
  case taskList(isTight: Bool, items: [RawTaskListItem])
  case codeBlock(fenceInfo: String?, content: String)
  case htmlBlock(content: String)
  case paragraph(content: [InlineNode])
  case heading(level: Int, content: [InlineNode])
  case table(columnAlignments: [RawTableColumnAlignment], rows: [RawTableRow])
  case thematicBreak
}

extension BlockNode {
  public var children: [BlockNode] {
    switch self {
    case .blockquote(let children):
      return children
    case .bulletedList(_, let items):
      return items.map(\.children).flatMap { $0 }
    case .numberedList(_, _, let items):
      return items.map(\.children).flatMap { $0 }
    case .taskList(_, let items):
      return items.map(\.children).flatMap { $0 }
    default:
      return []
    }
  }

  public var isParagraph: Bool {
    guard case .paragraph = self else { return false }
    return true
  }
}

public struct RawListItem: Hashable {
  public let children: [BlockNode]
  public init(children: [BlockNode]) { self.children = children }
}

public struct RawTaskListItem: Hashable {
  public let isCompleted: Bool
  public let children: [BlockNode]
  public init(isCompleted: Bool, children: [BlockNode]) {
    self.isCompleted = isCompleted
    self.children = children
  }
}

public enum RawTableColumnAlignment: Character {
  case none = "\0"
  case left = "l"
  case center = "c"
  case right = "r"
}

public struct RawTableRow: Hashable {
  public let cells: [RawTableCell]
  public init(cells: [RawTableCell]) { self.cells = cells }
}

public struct RawTableCell: Hashable {
  public let content: [InlineNode]
  public init(content: [InlineNode]) { self.content = content }
}