//
//  MarklySectionObserver.swift
//  Markly
//
//  An environment closure a heading reports its `MarklySectionID` to when it appears, so the
//  reader controller can track the current section (for TOC highlighting and reading-position
//  persistence). Defaults to a no-op so `MarklyBlockView` can be used without a controller.
//
//  The closure is `@MainActor`-isolated: it runs from `.onAppear` (always main-actor), and a
//  `@MainActor` closure is `Sendable` — which lets the `EnvironmentKey` default satisfy Swift 6
//  strict concurrency without a mutable-global warning.
//

import SwiftUI

private struct MarklySectionObserverKey: EnvironmentKey {
    static let defaultValue: @MainActor (MarklySectionID) -> Void = { _ in }
}

extension EnvironmentValues {
    /// Called with a heading's section id when it appears on screen.
    var marklySectionObserver: @MainActor (MarklySectionID) -> Void {
        get { self[MarklySectionObserverKey.self] }
        set { self[MarklySectionObserverKey.self] = newValue }
    }
}