import SwiftUI

// Vendored from gonzalezreal/swift-markdown-ui (MIT; Copyright (c) 2020 Guillermo Gonzalez).
//
// `Theme+GitHub` bakes a fixed GitHub palette into its block-style closures via `fileprivate`
// `Color` statics. Markly needs those same GitHub block layouts but driven by the Cosmos color
// tokens (so code cards, heading dividers, and rules adapt to the reader's paper style), and
// `Color` values are only available at runtime from `@Environment(\.cosmosTheme)`. This file
// therefore exposes a parameterized builder — `Theme.marklyGitHub(...)` — that mirrors the
// GitHub theme exactly but takes every color as an argument.
//
// This builder lives in the MarkdownUI target (Swift 5 language mode) on purpose: the block-style
// closures call `Divider()`, `VStack`, `RoundedRectangle`, `ScrollView`, and other SwiftUI view
// initializers that are MainActor-isolated in the OS 26 SDK. Free `@ViewBuilder` closures are not
// MainActor-isolated, so constructing them under Swift 6 strict concurrency (Markly's mode) would
// raise "call to main actor-isolated initializer in a non-isolated context". Keeping the closure
// construction in the Swift 5 target avoids that, and Markly simply calls this function with
// Cosmos-derived colors. Markly then overrides the code-block style with its own copy-button
// card (a single `MarklyCodeBlockCard` initializer call, which is not MainActor-isolated).
extension Theme {
  /// A GitHub-style theme whose colors are supplied by the caller, so a consumer can drive the
  /// palette from its own design system (Markly drives it from Cosmos color tokens).
  ///
  /// - Parameters:
  ///   - text: Primary inline/paragraph text color.
  ///   - secondaryText: Blockquote / muted text color.
  ///   - tertiaryText: Level-6 heading color.
  ///   - background: Page / table odd-row background.
  ///   - secondaryBackground: Code-block, table even-row, and elevated-surface background.
  ///   - link: Link color.
  ///   - border: Hairline / table-border / rule color.
  ///   - divider: Heading underline color.
  public static func marklyGitHub(
    text: Color,
    secondaryText: Color,
    tertiaryText: Color,
    background: Color,
    secondaryBackground: Color,
    link: Color,
    border: Color,
    divider: Color
  ) -> Theme {
    Theme()
      .text {
        ForegroundColor(text)
        BackgroundColor(background)
        FontSize(16)
      }
      .code {
        FontFamilyVariant(.monospaced)
        FontSize(.em(0.85))
        BackgroundColor(secondaryBackground)
      }
      .strong {
        FontWeight(.semibold)
      }
      .link {
        ForegroundColor(link)
      }
      .heading1 { configuration in
        VStack(alignment: .leading, spacing: 0) {
          configuration.label
            .relativePadding(.bottom, length: .em(0.3))
            .relativeLineSpacing(.em(0.125))
            .markdownMargin(top: 24, bottom: 16)
            .markdownTextStyle {
              FontWeight(.semibold)
              FontSize(.em(2))
            }
          Divider().overlay(divider)
        }
      }
      .heading2 { configuration in
        VStack(alignment: .leading, spacing: 0) {
          configuration.label
            .relativePadding(.bottom, length: .em(0.3))
            .relativeLineSpacing(.em(0.125))
            .markdownMargin(top: 24, bottom: 16)
            .markdownTextStyle {
              FontWeight(.semibold)
              FontSize(.em(1.5))
            }
          Divider().overlay(divider)
        }
      }
      .heading3 { configuration in
        configuration.label
          .relativeLineSpacing(.em(0.125))
          .markdownMargin(top: 24, bottom: 16)
          .markdownTextStyle {
            FontWeight(.semibold)
            FontSize(.em(1.25))
          }
      }
      .heading4 { configuration in
        configuration.label
          .relativeLineSpacing(.em(0.125))
          .markdownMargin(top: 24, bottom: 16)
          .markdownTextStyle {
            FontWeight(.semibold)
          }
      }
      .heading5 { configuration in
        configuration.label
          .relativeLineSpacing(.em(0.125))
          .markdownMargin(top: 24, bottom: 16)
          .markdownTextStyle {
            FontWeight(.semibold)
            FontSize(.em(0.875))
          }
      }
      .heading6 { configuration in
        configuration.label
          .relativeLineSpacing(.em(0.125))
          .markdownMargin(top: 24, bottom: 16)
          .markdownTextStyle {
            FontWeight(.semibold)
            FontSize(.em(0.85))
            ForegroundColor(tertiaryText)
          }
      }
      .paragraph { configuration in
        configuration.label
          .fixedSize(horizontal: false, vertical: true)
          .relativeLineSpacing(.em(0.25))
          .markdownMargin(top: 0, bottom: 16)
      }
      .blockquote { configuration in
        HStack(spacing: 0) {
          RoundedRectangle(cornerRadius: 6)
            .fill(border)
            .relativeFrame(width: .em(0.2))
          configuration.label
            .markdownTextStyle { ForegroundColor(secondaryText) }
            .relativePadding(.horizontal, length: .em(1))
        }
        .fixedSize(horizontal: false, vertical: true)
      }
      .codeBlock { configuration in
        ScrollView(.horizontal) {
          configuration.label
            .fixedSize(horizontal: false, vertical: true)
            .relativeLineSpacing(.em(0.225))
            .markdownTextStyle {
              FontFamilyVariant(.monospaced)
              FontSize(.em(0.85))
            }
            .padding(16)
        }
        .background(secondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .markdownMargin(top: 0, bottom: 16)
      }
      .listItem { configuration in
        configuration.label
          .markdownMargin(top: .em(0.25))
      }
      .taskListMarker { configuration in
        Image(systemName: configuration.isCompleted ? "checkmark.square.fill" : "square")
          .symbolRenderingMode(.hierarchical)
          .foregroundStyle(Color(rgba: 0xb9b9_bbff), Color(rgba: 0xeeee_efff))
          .imageScale(.small)
          .relativeFrame(minWidth: .em(1.5), alignment: .trailing)
      }
      .table { configuration in
        configuration.label
          .fixedSize(horizontal: false, vertical: true)
          .markdownTableBorderStyle(.init(color: border))
          .markdownTableBackgroundStyle(
            .alternatingRows(background, secondaryBackground)
          )
          .markdownMargin(top: 0, bottom: 16)
      }
      .tableCell { configuration in
        configuration.label
          .markdownTextStyle {
            if configuration.row == 0 {
              FontWeight(.semibold)
            }
            BackgroundColor(nil)
          }
          .fixedSize(horizontal: false, vertical: true)
          .padding(.vertical, 6)
          .padding(.horizontal, 13)
          .relativeLineSpacing(.em(0.25))
      }
      .thematicBreak {
        Divider()
          .relativeFrame(height: .em(0.25))
          .overlay(border)
          .markdownMargin(top: 24, bottom: 24)
      }
  }
}