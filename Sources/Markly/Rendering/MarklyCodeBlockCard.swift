//
//  MarklyCodeBlockCard.swift
//
//  The Markly code-block chrome: a horizontal-scrolling code surface on a Cosmos-colored card
//  with a language label and a Copy-to-clipboard button. The code *content* itself is supplied
//  by MarkdownUI's `CodeBlockView` as `configuration.label` — the `CodeSyntaxHighlighter`-produced
//  text view (`.plainText` by default; an Apple-only token lexer can be wired later via
//  `.markdownCodeSyntaxHighlighter`). This card wraps that label, so Markly uses MarkdownUI's
//  code-block machinery + syntax-highlighter protocol while keeping its e-reader chrome (Copy
//  button, Cosmos card, Apple-only clipboard). Replaces the standalone `MarklyCodeBlockView`,
//  which rendered its own `Text(verbatim:)`. See docs/Architecture.md §3, §10.
//

import SwiftUI
import Cosmos
import MarkdownUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// A code-block card wrapping a MarkdownUI-rendered code label, with a Copy button.
struct MarklyCodeBlockCard: View {
    /// The MarkdownUI-rendered code label (the syntax-highlighted code, as a view).
    let label: CodeBlockConfiguration.Label
    /// The info-string language (e.g. `"swift"`), if present.
    let language: String?
    /// The raw code content, used for the Copy button.
    let code: String

    @Environment(\.cosmosTheme) private var theme
    @Environment(\.marklyMarkdownTheme) private var md

    var body: some View {
        VStack(alignment: .leading, spacing: CosmosSpacingTokens.small) {
            ScrollView(.horizontal, showsIndicators: false) {
                label
                    // The label is a `Text`; apply Markly's monospaced reading font + Cosmos color
                    // explicitly so the code is monospaced and adapts to the paper style regardless
                    // of the syntax highlighter's default. `.body` is Dynamic-Type-relative, so the
                    // reader's font-size slider (`.dynamicTypeSize`) scales it.
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(theme.colors.primary)
                    .accessibilityTextContentType(.sourceCode)
                    // Take the intrinsic unwrapped width so long lines overflow the scroll viewport
                    // instead of wrapping — otherwise the horizontal ScrollView never engages.
                    .fixedSize(horizontal: true, vertical: false)
            }

            HStack(spacing: CosmosSpacingTokens.small) {
                if let language, !language.isEmpty {
                    Text(verbatim: language)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(theme.colors.secondary)
                }
                Spacer()
                if canCopy {
                    Button(action: copy) {
                        Label {
                            Text("Copy", bundle: .module)
                        } icon: {
                            Image(systemName: "doc.on.doc")
                        }
                        .font(.caption)
                    }
                }
            }
        }
        .padding(md.codePadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.colors.surface)
        // A content surface nested in the page → a moderate corner radius (smaller than the large
        // floating toolbar, larger than a chip).
        .clipShape(RoundedRectangle(cornerRadius: md.codeCornerRadius, style: .continuous))
    }

    /// `UIPasteboard` is unavailable on tvOS, so the Copy button is hidden there (no general
    /// pasteboard to write to). macOS/iOS/visionOS support copy.
    private var canCopy: Bool {
        #if os(tvOS)
        return false
        #else
        return true
        #endif
    }

    private func copy() {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
        #elseif os(iOS) || os(visionOS)
        UIPasteboard.general.string = code
        #else
        // tvOS: no general pasteboard; the Copy button is hidden, so this is unreachable.
        #endif
    }
}