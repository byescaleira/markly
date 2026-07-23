//
//  SoftBreak.swift
//  MarkdownUI
//
//  Vendored from gonzalezreal/swift-markdown-ui (MIT; Copyright (c) 2020 Guillermo Gonzalez).
//  Trimmed for Markly: only the `SoftBreak.Mode` enum is retained. The DSL inline-element
//  `SoftBreak()` (which conformed to `InlineContentProtocol`, part of the programmatic DSL not
//  vendored here) was removed. `Mode` is required by the inline renderer and the soft-break-mode
//  environment key.
//

import Foundation

/// The mode in which a soft break in Markdown content is rendered.
public enum SoftBreak {
  public enum Mode {
    /// Treat a soft break as a space.
    case space
    /// Treat a soft break as a line break.
    case lineBreak
  }
}