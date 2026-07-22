//
//  MarklyReaderTheme.swift
//  Markly
//
//  Reader themes (light/dark/sepia/night) modeled by Markly and mapped each to a `CosmosTheme`.
//  Cosmos has no named-appearance concept: `CosmosColorTokens` holds concrete `Color` values
//  and relies on SwiftUI adaptive colors for light/dark, so Markly models the reader palette
//  itself. `.light`/`.dark` reuse Cosmos's adaptive default tokens; `.sepia`/`.night` override
//  with explicit reader palettes. See docs/Architecture.md §7.
//

import SwiftUI
import Cosmos

/// A reader color theme.
public enum MarklyReaderTheme: String, Sendable, Equatable, CaseIterable, Codable {
    /// System-adaptive light theme.
    case light
    /// System-adaptive dark theme.
    case dark
    /// Warm sepia theme for long-form reading.
    case sepia
    /// High-contrast night theme.
    case night

    /// The `CosmosTheme` to inject for this reader theme.
    public var cosmosTheme: CosmosTheme {
        switch self {
        case .light: CosmosTheme.default.withColors(.marklyLight)
        case .dark: CosmosTheme.default.withColors(.marklyDark)
        case .sepia: CosmosTheme.default.withColors(.marklySepia)
        case .night: CosmosTheme.default.withColors(.marklyNight)
        }
    }
}

extension CosmosColorTokens {
    /// Light reader tokens — Cosmos's adaptive defaults (system foreground/background).
    static var marklyLight: CosmosColorTokens { .default }

    /// Dark reader tokens — Cosmos's adaptive defaults (the system resolves them dark).
    static var marklyDark: CosmosColorTokens { .default }

    /// Sepia reader tokens — warm paper-like palette.
    static var marklySepia: CosmosColorTokens {
        CosmosColorTokens(
            primary: Color(red: 0.27, green: 0.20, blue: 0.13),
            secondary: Color(red: 0.40, green: 0.31, blue: 0.20),
            accent: Color(red: 0.40, green: 0.27, blue: 0.13),
            background: Color(red: 0.96, green: 0.91, blue: 0.78),
            surface: Color(red: 0.93, green: 0.87, blue: 0.72),
            success: .green,
            warning: .orange,
            error: .red,
            outline: Color(red: 0.78, green: 0.70, blue: 0.55)
        )
    }

    /// Night reader tokens — dark, low-glare palette.
    static var marklyNight: CosmosColorTokens {
        CosmosColorTokens(
            primary: Color(red: 0.85, green: 0.85, blue: 0.90),
            secondary: Color(red: 0.65, green: 0.65, blue: 0.70),
            accent: .gray,
            background: .black,
            surface: Color(red: 0.08, green: 0.08, blue: 0.10),
            success: .green,
            warning: .orange,
            error: .red,
            outline: Color(red: 0.20, green: 0.20, blue: 0.24)
        )
    }
}