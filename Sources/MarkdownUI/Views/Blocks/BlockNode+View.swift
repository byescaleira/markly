import SwiftUI

// Vendored from gonzalezreal/swift-markdown-ui (MIT; Copyright (c) 2020 Guillermo Gonzalez).
// Conformance raised to `public` so Markly can render a `BlockNode` as a SwiftUI view. Swift does
// not allow `public` on an extension that declares a protocol conformance; the conformance of a
// `public` type is visible to other modules as long as the conforming member (`body`) is public,
// so the extension stays access-less and only `body` is marked `public`. The individual block
// views (HeadingView, BlockquoteView, …) stay internal to this module; they are returned opaquely
// as `some View` from `body`, so Markly never names them.
extension BlockNode: View {
  public var body: some View {
    switch self {
    case .blockquote(let children):
      BlockquoteView(children: children)
    case .bulletedList(let isTight, let items):
      BulletedListView(isTight: isTight, items: items)
    case .numberedList(let isTight, let start, let items):
      NumberedListView(isTight: isTight, start: start, items: items)
    case .taskList(let isTight, let items):
      TaskListView(isTight: isTight, items: items)
    case .codeBlock(let fenceInfo, let content):
      CodeBlockView(fenceInfo: fenceInfo, content: content)
    case .htmlBlock(let content):
      ParagraphView(content: content)
    case .paragraph(let content):
      ParagraphView(content: content)
    case .heading(let level, let content):
      HeadingView(level: level, content: content)
    case .table(let columnAlignments, let rows):
      // Markly targets .v26 (≥ the iOS 16 / macOS 13 / tvOS 16 / watchOS 9 Grid floor), so the
      // availability gate is always satisfied — kept for parity with upstream.
      if #available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *) {
        TableView(columnAlignments: columnAlignments, rows: rows)
      }
    case .thematicBreak:
      ThematicBreakView()
    }
  }
}
