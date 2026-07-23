//
//  MarklyCodeBlockView.swift
//  Markly
//
//  Renders a code block as plain monospaced text on a surface-colored card with a Copy
//  button. Apple-only: no third-party syntax highlighter (see docs/Architecture.md §10).
//  Token coloring is deferred to a future Markly-internal lightweight lexer applied as
//  `AttributeContainer` runs — still Apple-only.
//

import SwiftUI
import Cosmos

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Renders a fenced/indented code block with a copy-to-clipboard button.
struct MarklyCodeBlockView: View {
    /// The info-string language (e.g. `"swift"`), if present.
    let language: String?
    /// The raw code content.
    let code: String

    @Environment(\.cosmosTheme) private var theme
    @Environment(\.marklyMarkdownTheme) private var md

    var body: some View {
        VStack(alignment: .leading, spacing: CosmosSpacingTokens.small) {
            ScrollView(.horizontal, showsIndicators: false) {
                Text(verbatim: code)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(theme.colors.primary)
                    .accessibilityTextContentType(.sourceCode)
                    // Take the intrinsic unwrapped width so long lines overflow the scroll
                    // viewport instead of wrapping — otherwise the horizontal ScrollView never
                    // engages and long code is unreadable.
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
        // A content surface nested in the page → iOS 26 uses a moderate corner radius (smaller
        // than the large floating toolbar, larger than a chip).
        .clipShape(RoundedRectangle(cornerRadius: md.codeCornerRadius, style: .continuous))
    }

    /// `UIPasteboard` is unavailable on tvOS, so the Copy button is hidden there (no
    /// general pasteboard to write to). macOS/iOS/visionOS support copy.
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