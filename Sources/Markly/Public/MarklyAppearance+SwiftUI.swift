//
//  MarklyAppearance+SwiftUI.swift
//  Markly
//
//  SwiftUI-only accessors for the appearance enums declared in `MarklyPaperStyle.swift`
//  (Foundation-only): `PaperStyle` → concrete `MarklyReaderTheme`, `MarklyFontSize` →
//  `DynamicTypeSize`, and `MarklyHighlightColor` → SwiftUI `Color`. Keeping these here lets the
//  persisted settings model stay Foundation-only while the view layer resolves them.
//

import SwiftUI

extension PaperStyle {
    /// Resolves this paper style to a concrete reader theme, following the system appearance for
    /// `.auto`.
    public func resolvedTheme(colorScheme: ColorScheme) -> MarklyReaderTheme {
        switch self {
        case .white: .light
        case .sepia: .sepia
        case .night: .night
        case .dark: .dark
        case .auto: colorScheme == .dark ? .dark : .light
        }
    }

    /// The concrete theme to seed when no system color scheme is known yet (`.auto` → `.light`).
    public var fallbackTheme: MarklyReaderTheme {
        switch self {
        case .white: .light
        case .sepia: .sepia
        case .night: .night
        case .dark: .dark
        case .auto: .light
        }
    }

    /// The paper style that corresponds to a concrete (non-auto) reader theme, or `.auto` if the
    /// theme should follow the system (used only to round-trip a legacy seeded theme).
    public static func from(theme: MarklyReaderTheme) -> PaperStyle {
        switch theme {
        case .light: .white
        case .dark: .dark
        case .sepia: .sepia
        case .night: .night
        }
    }
}

extension MarklyFontSize {
    /// The SwiftUI `DynamicTypeSize` this step maps to. Cosmos typography tokens are
    /// `.system(textStyle)` (Dynamic-Type-relative), so applying `.dynamicTypeSize(_:)` with this
    /// value scales them with correct reflow.
    public var dynamicTypeSize: DynamicTypeSize {
        switch self {
        case .extraSmall: .xSmall
        case .small: .small
        case .medium: .medium
        case .large: .large
        case .extraLarge: .xLarge
        case .extraExtraLarge: .xxLarge
        case .accessibilityLarge: .accessibility1
        }
    }

    /// A linear scale factor for this step relative to `.large` (the default). Used to size the
    /// selectable `UITextView`/`NSTextView` body font, which — unlike SwiftUI `Text` — cannot be
    /// driven directly by `.dynamicTypeSize`. The factors are Apple-Books-style discrete steps; the
    /// same factor is applied on every platform so body text scales consistently across iOS, macOS,
    /// and visionOS. (Headings, which use SwiftUI `Text`, scale via `dynamicTypeSize` instead.)
    public var scale: CGFloat {
        switch self {
        case .extraSmall: 0.85
        case .small: 0.92
        case .medium: 0.96
        case .large: 1.0
        case .extraLarge: 1.12
        case .extraExtraLarge: 1.25
        case .accessibilityLarge: 1.5
        }
    }
}

extension MarklyHighlightColor {
    /// The SwiftUI tint for this highlight, or `nil` for `.underline` (drawn as a stroke). The
    /// pastel set matches Apple Books' highlight palette, tuned to read with dark text.
    public var color: Color {
        switch self {
        case .underline: Color.accentColor
        case .green: Color(red: 0.686, green: 0.835, blue: 0.592) // #AFD597
        case .blue: Color(red: 0.710, green: 0.804, blue: 0.933) // #B5CDEE
        case .yellow: Color(red: 0.976, green: 0.835, blue: 0.424) // #F9D56C
        case .pink: Color(red: 0.949, green: 0.698, blue: 0.737) // #F2B2BC
        case .purple: Color(red: 0.839, green: 0.753, blue: 0.933) // #D6C0EE
        }
    }

    /// A translucent version of the tint suitable as a text background (Apple Books draws
    /// highlights as a semi-transparent wash, not a solid fill).
    public var backgroundColor: Color {
        color.opacity(0.45)
    }
}