//
//  MarklyMarkdownRenderTests.swift
//
//  Diagnostic: confirm `MarklyMarkdown` actually draws content. `ImageRenderer` does a single
//  synchronous layout pass and does NOT run `.task`, so this catches a blank-render regression
//  where the view depends on an async parse that hasn't resolved.
//

import Testing
import SwiftUI
@testable import Markly

@Suite("MarklyMarkdown render")
struct MarklyMarkdownRenderTests {

    @Test @MainActor func rendersNonBlankContent() {
        let view = MarklyMarkdown("# Hello\n\nA paragraph with **bold**, *italic*, and `code`.")
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        #if os(macOS)
        let image = renderer.nsImage
        let size = image?.size ?? .zero
        #else
        let image = renderer.uiImage
        let size = image?.size ?? .zero
        #endif
        #expect(image != nil, "ImageRenderer returned no image")
        #expect(size.height > 5, "MarklyMarkdown rendered blank (height=\(size.height))")
    }

    @Test @MainActor func emptyMarkdownRendersNothing() {
        let view = MarklyMarkdown("")
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        #if os(macOS)
        let size = renderer.nsImage?.size ?? .zero
        #else
        let size = renderer.uiImage?.size ?? .zero
        #endif
        #expect(size.height <= 5, "Empty markdown should render blank (height=\(size.height))")
    }
}