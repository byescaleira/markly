//
//  MarklyErrorConfig.swift
//  Markly
//
//  The optional host wiring for Nebula's error + logging subsystems. `Markly.configure()` is
//  **opt-in**: Markly never force-installs global process state. Without it, `MarklyReader`
//  reports errors through the process-wide `.default` configs (a no-op report handler and a
//  user-message map returning `nil`), and the reader falls back to its own localized "Unable
//  to load this book." surface. Calling `Markly.configure()` upgrades that to Markly-scoped
//  logs (subsystem/category in Console.app) and value-based recovery actions
//  (``NebulaUserError``) resolved per `MarklyCode`.
//
//  All messages emitted here are developer-facing English, per Nebula's convention — the host
//  localizes `RecoveryAction` cases into its own bundle at the presentation layer. Markly's
//  own reader chrome localizes the common verbs ("Retry"/"Cancel"/"Dismiss") via
//  `Bundle.module`; see MarklyReader.swift.
//
//  See docs/Architecture.md §6.
//

import Foundation
import Nebula

extension Markly {

    /// The Markly-scoped error configuration: category `"Markly"` and a user-message map that
    /// resolves `MarklyCode` metadata (set by `MarklySourceError`/`MarklyParseError`/
    /// `MarklyRenderError`) to a ``NebulaUserError`` with value-based recovery actions, falling
    /// back to ``NebulaUserError.default(for:context:)`` for unknown codes.
    public static let defaultErrorConfiguration: NebulaErrorConfiguration = .default
        .withCategory("Markly")
        .withUserMessageMap { kind, metadata in
            switch metadata["MarklyCode"] {
            case "source-unavailable":
                return NebulaUserError(
                    message: "Couldn’t open this book.",
                    recoveryActions: [.retry, .dismiss]
                )
            case "parse-failed":
                return NebulaUserError(
                    message: "Couldn’t read this book.",
                    recoveryActions: [.dismiss]
                )
            case "render-failed":
                return NebulaUserError(
                    message: "Couldn’t display part of this book.",
                    recoveryActions: [.dismiss]
                )
            default:
                return NebulaUserError.default(for: kind, context: metadata)
            }
        }

    /// Builds a Markly-scoped logging configuration for the given subsystem (the host's bundle
    /// identifier by convention), so Markly's logs are filterable in Console.app.
    public static func defaultLogConfiguration(subsystem: String) -> NebulaLogConfiguration {
        .default.withSubsystem(subsystem).withCategory("Markly")
    }

    /// Installs Markly's default error + logging configurations as the process-wide Nebula
    /// configs. Call once at app launch (before constructing a `MarklyReader`) so Markly's
    /// instrumented parse use case and load-failure path log under the given subsystem and
    /// resolve per-`MarklyCode` recovery actions.
    ///
    /// - Parameter subsystem: The logging subsystem (typically the host's bundle identifier).
    ///   Defaults to `"com.markly.reader"`.
    public static func configure(subsystem: String = "com.markly.reader") {
        NebulaLogConfig.set(defaultLogConfiguration(subsystem: subsystem))
        NebulaErrorConfig.set(defaultErrorConfiguration)
    }
}