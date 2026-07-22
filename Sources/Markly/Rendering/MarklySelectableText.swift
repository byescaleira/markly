//
//  MarklySelectableText.swift
//  Markly
//
//  A selectable text view that renders a paragraph's inline markdown with existing highlights
//  drawn as background colors / underlines, and reports the user's text selection as a character
//  range into the block's plain text (the same coordinate `MarklyHighlight.range` uses).
//
//  SwiftUI's `Text` cannot capture a text selection range (`.textSelection(.enabled)` only lets
//  the user copy), so free-form highlights require a real text view: `UITextView` on
//  iOS/iPadOS/visionOS and `NSTextView` on macOS. Both are Apple-only (UIKit/AppKit). tvOS has no
//  text selection, so paragraphs there keep the non-selectable `MarklyInlineText` (`Text`) path.
//
//  Formatting is built through Foundation's `NSAttributedString(markdown:)` (the UIKit/AppKit-native
//  counterpart of `AttributedString(markdown:)`), so bold/italic/strikethrough render correctly in
//  the text view. Fonts are re-scaled to the reader's `MarklyFontSize` via `UIFontMetrics`/
//  `NSFontMetrics` (the same scaling SwiftUI's `.dynamicTypeSize` uses), preserving bold/italic
//  traits. Highlight backgrounds/underlines are applied as attributed-string attributes over the
//  stored character ranges. See docs/Architecture.md §3, §10.
//

import SwiftUI
import Cosmos
import Foundation

#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

/// Renders a paragraph as selectable text with highlights, reporting the selected character range.
struct MarklySelectableText: View {
    let inlines: [MarklyInline]
    let basePointSize: CGFloat
    let textColor: Color
    let fontSize: MarklyFontSize
    let highlights: [MarklyHighlight]
    let onSelection: (Range<Int>?) -> Void

    var body: some View {
        #if os(macOS)
        MarklySelectableNSText(
            inlines: inlines,
            basePointSize: basePointSize,
            textColor: textColor,
            fontSize: fontSize,
            highlights: highlights,
            onSelection: onSelection
        )
        #elseif os(tvOS)
        // tvOS has no text selection: fall back to the non-selectable SwiftUI Text path. Highlights
        // remain visible only in the Highlights list sheet (excerpts), not inline here.
        MarklyInlineText(inlines: inlines)
        #else
        MarklySelectableUIText(
            inlines: inlines,
            basePointSize: basePointSize,
            textColor: textColor,
            fontSize: fontSize,
            highlights: highlights,
            onSelection: onSelection
        )
        #endif
    }
}

// MARK: - Highlight application (shared)

/// Applies highlight background/underline attributes to an immutable `NSAttributedString` over the
/// stored character ranges, returning a new attributed string. Used by both the UIKit and AppKit
/// selectable text views (the platform color type is resolved per-platform at the call site).
enum MarklyHighlightStyler {
    /// The character range of a highlight, clamped to the attributed string's length.
    static func nsRange(for highlight: MarklyHighlight, in length: Int) -> NSRange {
        let lower = max(0, min(highlight.range.lowerBound, length))
        let upper = max(lower, min(highlight.range.upperBound, length))
        return NSRange(location: lower, length: upper - lower)
    }
}

#if canImport(UIKit) && !os(tvOS)

// MARK: - UIKit (iOS / iPadOS / visionOS)

struct MarklySelectableUIText: UIViewRepresentable {
    let inlines: [MarklyInline]
    let basePointSize: CGFloat
    let textColor: Color
    let fontSize: MarklyFontSize
    let highlights: [MarklyHighlight]
    let onSelection: (Range<Int>?) -> Void

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = false
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.adjustsFontForContentSizeCategory = false
        context.coordinator.update(inlines: inlines, basePointSize: basePointSize, textColor: textColor, fontSize: fontSize, highlights: highlights, into: textView)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.onSelection = onSelection
        context.coordinator.update(inlines: inlines, basePointSize: basePointSize, textColor: textColor, fontSize: fontSize, highlights: highlights, into: textView)
    }

    func makeCoordinator() -> Coordinator { Coordinator(onSelection: onSelection) }

    @MainActor final class Coordinator: NSObject, UITextViewDelegate {
        var onSelection: (Range<Int>?) -> Void
        private var lastReported: Range<Int>??

        init(onSelection: @escaping (Range<Int>?) -> Void) {
            self.onSelection = onSelection
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            let range = textView.selectedRange
            let selection: Range<Int>? = range.length > 0
                ? range.location..<(range.location + range.length)
                : nil
            // Only report changes (avoids a feedback loop on re-render).
            guard selection != (lastReported ?? nil) else { return }
            lastReported = selection
            onSelection(selection)
        }

        func update(
            inlines: [MarklyInline], basePointSize: CGFloat, textColor: Color,
            fontSize: MarklyFontSize, highlights: [MarklyHighlight], into textView: UITextView
        ) {
            guard let attributed = Self.makeAttributed(
                inlines: inlines, basePointSize: basePointSize, textColor: textColor,
                fontSize: fontSize, highlights: highlights
            ) else {
                textView.attributedText = nil
                return
            }
            textView.attributedText = attributed
        }

        static func makeAttributed(
            inlines: [MarklyInline], basePointSize: CGFloat, textColor: Color,
            fontSize: MarklyFontSize, highlights: [MarklyHighlight]
        ) -> NSAttributedString? {
            let markdown = MarklyInlineSerializer.toMarkdown(inlines)
            let options = AttributedString.MarkdownParsingOptions(
                allowsExtendedAttributes: true,
                interpretedSyntax: .inlineOnlyPreservingWhitespace,
                failurePolicy: .returnPartiallyParsedIfPossible
            )
            guard let parsed = try? NSAttributedString(markdown: markdown, options: options, baseURL: nil) else {
                return nil
            }
            let mutable = NSMutableAttributedString(attributedString: parsed)
            let scaledSize = Self.scaledBodySize(basePointSize: basePointSize, fontSize: fontSize)
            // Re-scale every run's font to the reader size while preserving bold/italic traits.
            let fullRange = NSRange(location: 0, length: mutable.length)
            mutable.enumerateAttribute(.font, in: fullRange, options: []) { value, range, _ in
                guard let font = value as? UIFont else { return }
                let descriptor = font.fontDescriptor.withSize(scaledSize)
                mutable.addAttribute(.font, value: UIFont(descriptor: descriptor, size: scaledSize), range: range)
            }
            // Base text color for runs without an explicit foreground (links keep their tint).
            mutable.addAttribute(.foregroundColor, value: UIColor(textColor), range: fullRange)
            // Apply highlights.
            for highlight in highlights {
                let range = MarklyHighlightStyler.nsRange(for: highlight, in: mutable.length)
                if range.length == 0 { continue }
                if highlight.color.isUnderline {
                    mutable.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
                    mutable.addAttribute(.underlineColor, value: UIColor(highlight.color.color), range: range)
                } else {
                    mutable.addAttribute(.backgroundColor, value: UIColor(highlight.color.backgroundColor), range: range)
                }
            }
            return mutable
        }

        /// The body point size for the reader's font-size step (a linear scale of the base body
        /// size; see `MarklyFontSize.scale`).
        static func scaledBodySize(basePointSize: CGFloat, fontSize: MarklyFontSize) -> CGFloat {
            basePointSize * fontSize.scale
        }
    }
}

#endif

#if os(macOS)

// MARK: - AppKit (macOS)

struct MarklySelectableNSText: NSViewRepresentable {
    let inlines: [MarklyInline]
    let basePointSize: CGFloat
    let textColor: Color
    let fontSize: MarklyFontSize
    let highlights: [MarklyHighlight]
    let onSelection: (Range<Int>?) -> Void

    func makeNSView(context: Context) -> MarklySelectableTextHostView {
        let host = MarklySelectableTextHostView()
        host.textView.delegate = context.coordinator
        host.apply(inlines: inlines, basePointSize: basePointSize, textColor: textColor, fontSize: fontSize, highlights: highlights)
        return host
    }

    func updateNSView(_ host: MarklySelectableTextHostView, context: Context) {
        context.coordinator.onSelection = onSelection
        host.apply(inlines: inlines, basePointSize: basePointSize, textColor: textColor, fontSize: fontSize, highlights: highlights)
    }

    func makeCoordinator() -> Coordinator { Coordinator(onSelection: onSelection) }

    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        var onSelection: (Range<Int>?) -> Void
        private var lastReported: Range<Int>??

        init(onSelection: @escaping (Range<Int>?) -> Void) {
            self.onSelection = onSelection
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let range = textView.selectedRange()
            let selection: Range<Int>? = range.length > 0
                ? range.location..<(range.location + range.length)
                : nil
            guard selection != (lastReported ?? nil) else { return }
            lastReported = selection
            onSelection(selection)
        }
    }
}

/// A self-sizing `NSView` that hosts a non-editable, selectable `NSTextView` and reports its laid-out
/// height via `intrinsicContentSize`, so SwiftUI sizes it to fit the text. The text view itself never
/// scrolls (the outer SwiftUI `ScrollView` handles scrolling); it only needs to grow vertically to
/// its content. Width is driven by SwiftUI through the host's frame, tracked into the text container.
@MainActor
final class MarklySelectableTextHostView: NSView {

    let textView: NSTextView

    override init(frame frameRect: NSRect) {
        let textView = NSTextView()
        self.textView = textView
        super.init(frame: frameRect)
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.autoresizingMask = [.width]
        addSubview(textView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// The laid-out text height, plus the text-container inset, as the host's intrinsic height. The
    /// width is left to SwiftUI (`noIntrinsicMetric`).
    override var intrinsicContentSize: NSSize {
        guard let container = textView.textContainer,
              let layoutManager = textView.layoutManager else {
            return NSSize(width: NSView.noIntrinsicMetric, height: 0)
        }
        layoutManager.ensureLayout(for: container)
        let used = layoutManager.usedRect(for: container)
        let verticalInset = textView.textContainerInset.height * 2
        return NSSize(width: NSView.noIntrinsicMetric, height: used.height + verticalInset)
    }

    /// Applies the attributed string (rebuilt from the inlines/highlights) and re-layouts at the
    /// current width, then invalidates the intrinsic size so SwiftUI re-measures.
    func apply(
        inlines: [MarklyInline], basePointSize: CGFloat, textColor: Color,
        fontSize: MarklyFontSize, highlights: [MarklyHighlight]
    ) {
        let built = Self.makeAttributed(
            inlines: inlines, basePointSize: basePointSize, textColor: textColor,
            fontSize: fontSize, highlights: highlights
        )
        textView.textStorage?.setAttributedString(built ?? NSAttributedString())
        relayout()
    }

    /// Re-measures the text container at the host's current width and tells SwiftUI the intrinsic
    /// size changed. Called on apply and from `layout()` (so window resizes reflow the text).
    private func relayout() {
        let width = max(0, bounds.width)
        textView.textContainer?.size = NSSize(
            width: width - textView.textContainerInset.width * 2,
            height: .greatestFiniteMagnitude
        )
        if let container = textView.textContainer, let layoutManager = textView.layoutManager {
            layoutManager.ensureLayout(for: container)
        }
        invalidateIntrinsicContentSize()
    }

    override func layout() {
        super.layout()
        // The frame (width) may have changed since the last apply; reflow to the new width.
        relayout()
    }

    static func makeAttributed(
        inlines: [MarklyInline], basePointSize: CGFloat, textColor: Color,
        fontSize: MarklyFontSize, highlights: [MarklyHighlight]
    ) -> NSAttributedString? {
        let markdown = MarklyInlineSerializer.toMarkdown(inlines)
        let options = AttributedString.MarkdownParsingOptions(
            allowsExtendedAttributes: true,
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        guard let parsed = try? NSAttributedString(markdown: markdown, options: options, baseURL: nil) else {
            return nil
        }
        let mutable = NSMutableAttributedString(attributedString: parsed)
        let scaledSize = basePointSize * fontSize.scale
        let fullRange = NSRange(location: 0, length: mutable.length)
        mutable.enumerateAttribute(.font, in: fullRange, options: []) { value, range, _ in
            guard let font = value as? NSFont else { return }
            let descriptor = font.fontDescriptor.withSize(scaledSize)
            // `NSFont(descriptor:size:)` is failable on macOS (unlike UIFont); fall back to the
            // original font if the descriptor can't be instantiated at the scaled size.
            let scaled = NSFont(descriptor: descriptor, size: scaledSize) ?? font
            mutable.addAttribute(.font, value: scaled, range: range)
        }
        mutable.addAttribute(.foregroundColor, value: NSColor(textColor), range: fullRange)
        for highlight in highlights {
            let range = MarklyHighlightStyler.nsRange(for: highlight, in: mutable.length)
            if range.length == 0 { continue }
            if highlight.color.isUnderline {
                mutable.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
                mutable.addAttribute(.underlineColor, value: NSColor(highlight.color.color), range: range)
            } else {
                mutable.addAttribute(.backgroundColor, value: NSColor(highlight.color.backgroundColor), range: range)
            }
        }
        return mutable
    }
}

#endif