//
//  MarklyPaperStyle.swift
//  Markly
//
//  The user-facing "paper style" selector (White / Sepia / Night / Dark / Auto), richer than the
//  legacy `MarklyReaderTheme` because it adds an `auto` case that follows the system color scheme.
//  The concrete `MarklyReaderTheme`/`CosmosTheme` resolution lives in SwiftUI-bearing code
//  (`Public/MarklyReaderTheme+PaperStyle.swift`); this enum stays Foundation-only so it can live
//  in `MarklyReaderSettings` without pulling SwiftUI into the persisted model.
//

import Foundation

/// The reader's paper (background) style.
public enum PaperStyle: String, Sendable, Equatable, Hashable, CaseIterable, Codable, Identifiable {
    /// Follow the system light/dark appearance.
    case auto
    /// White paper (light theme).
    case white
    /// Warm sepia paper.
    case sepia
    /// Dark, low-glare night paper.
    case night
    /// System-adaptive dark paper.
    case dark

    /// Identifiable id (the raw value).
    public var id: String { rawValue }

    /// `true` when this style follows the system appearance (no fixed theme).
    public var isAuto: Bool { self == .auto }
}

/// The reader's discrete font-size step. Maps to a SwiftUI `DynamicTypeSize` in SwiftUI-bearing
/// code so it reuses Cosmos typography tokens (which are Dynamic-Type-relative) and gives correct
/// text reflow. Apple Books exposes font size as discrete steps, independent of the system Dynamic
/// Type setting — this mirrors that.
public enum MarklyFontSize: String, Sendable, Equatable, Hashable, CaseIterable, Codable, Identifiable {
    /// Extra small.
    case extraSmall
    /// Small.
    case small
    /// Medium.
    case medium
    /// The system default size.
    case large
    /// Extra large.
    case extraLarge
    /// Extra extra large.
    case extraExtraLarge
    /// The first accessibility size.
    case accessibilityLarge

    /// Identifiable id (the raw value).
    public var id: String { rawValue }

    /// The default font size (matches the system default).
    public static let `default`: MarklyFontSize = .large

    /// The next larger step, or `nil` if this is already the largest.
    public var nextLarger: MarklyFontSize? {
        let all = MarklyFontSize.allCases
        guard let index = all.firstIndex(of: self), index + 1 < all.count else { return nil }
        return all[index + 1]
    }

    /// The next smaller step, or `nil` if this is already the smallest.
    public var nextSmaller: MarklyFontSize? {
        let all = MarklyFontSize.allCases
        guard let index = all.firstIndex(of: self), index - 1 >= 0 else { return nil }
        return all[index - 1]
    }

    /// A short label for the step (used by the tvOS font-size picker, where a slider isn't
    /// available).
    public var stepLabel: String {
        switch self {
        case .extraSmall: "XS"
        case .small: "S"
        case .medium: "M"
        case .large: "L"
        case .extraLarge: "XL"
        case .extraExtraLarge: "XXL"
        case .accessibilityLarge: "A+"
        }
    }
}