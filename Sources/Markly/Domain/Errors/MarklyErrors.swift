//
//  MarklyErrors.swift
//  Markly
//
//  Markly's Clean-Architecture layer errors: open structs conforming to Nebula's
//  ``NebulaFailure`` protocol, mirroring ``NebulaDomainError``. A layer error is an *input*
//  to the closed ``NebulaError/Kind`` envelope; the bridge kind is caller-picked via
//  ``toNebulaError(kind:)`` (defaulting to ``coarseKind``), and the fine `code` is carried
//  as `metadata["MarklyCode"]` so a ``NebulaErrorConfiguration`` user-message map can resolve
//  a per-code ``NebulaUserError``. See docs/Architecture.md §6.
//
//  Why three errors: source load (`book.source()`), parse (swift-markdown, total today but
//  modeled for future extension), and render (SwiftUI display). They share one shape so the
//  error-configuration map keys off `MarklyCode` uniformly. Today only the source path throws
//  in practice; the others are defined so the map and tests cover them, and so a host can
//  `throw MarklyParseError(...)` from a custom `MarklyBook`/pipeline without inventing a type.
//

import Foundation
import Nebula

/// A source-load error: `MarklyBook.source()` failed (the book's content could not be read).
public struct MarklySourceError: NebulaFailure, Equatable, Hashable {

    /// A fine-grained, Markly-defined error code (e.g. `"source-unavailable"`).
    public var code: String
    /// The human-facing message.
    public var message: String
    /// Free-form string metadata.
    public var metadata: [String: String]
    /// One nested underlying error (boxed to break struct recursion, reusing ``NebulaError/Box``).
    public var underlying: NebulaError.Box?

    /// Creates a source-load error.
    public init(
        code: String,
        message: String,
        metadata: [String: String] = [:],
        underlying: NebulaError.Box? = nil
    ) {
        self.code = code
        self.message = message
        self.metadata = metadata
        self.underlying = underlying
    }

    /// Source-load failures are content-access failures → `.file` (couldn't access the content).
    public var coarseKind: NebulaError.Kind { .file }

    /// Bridges to a ``NebulaError`` under `kind`. The fine `code` is preserved as
    /// `metadata["MarklyCode"]` for the user-message map.
    public func toNebulaError(kind: NebulaError.Kind) -> NebulaError {
        var meta = metadata
        meta["MarklyCode"] = code
        return NebulaError(
            code: NebulaError.Code(domain: "Markly.MarklySourceError", code: 0),
            kind: kind,
            message: message,
            metadata: meta,
            underlying: underlying
        )
    }
}

/// A parse error: the markdown could not be parsed into the block model.
public struct MarklyParseError: NebulaFailure, Equatable, Hashable {

    /// A fine-grained, Markly-defined error code (e.g. `"parse-failed"`).
    public var code: String
    /// The human-facing message.
    public var message: String
    /// Free-form string metadata.
    public var metadata: [String: String]
    /// One nested underlying error (boxed to break struct recursion).
    public var underlying: NebulaError.Box?

    /// Creates a parse error.
    public init(
        code: String,
        message: String,
        metadata: [String: String] = [:],
        underlying: NebulaError.Box? = nil
    ) {
        self.code = code
        self.message = message
        self.metadata = metadata
        self.underlying = underlying
    }

    /// Parse failures are read/decode failures → `.decoding`.
    public var coarseKind: NebulaError.Kind { .decoding }

    /// Bridges to a ``NebulaError`` under `kind`. The fine `code` is preserved as
    /// `metadata["MarklyCode"]`.
    public func toNebulaError(kind: NebulaError.Kind) -> NebulaError {
        var meta = metadata
        meta["MarklyCode"] = code
        return NebulaError(
            code: NebulaError.Code(domain: "Markly.MarklyParseError", code: 0),
            kind: kind,
            message: message,
            metadata: meta,
            underlying: underlying
        )
    }
}

/// A render error: a block could not be rendered into the SwiftUI surface.
public struct MarklyRenderError: NebulaFailure, Equatable, Hashable {

    /// A fine-grained, Markly-defined error code (e.g. `"render-failed"`).
    public var code: String
    /// The human-facing message.
    public var message: String
    /// Free-form string metadata.
    public var metadata: [String: String]
    /// One nested underlying error (boxed to break struct recursion).
    public var underlying: NebulaError.Box?

    /// Creates a render error.
    public init(
        code: String,
        message: String,
        metadata: [String: String] = [:],
        underlying: NebulaError.Box? = nil
    ) {
        self.code = code
        self.message = message
        self.metadata = metadata
        self.underlying = underlying
    }

    /// Render failures are Foundation/display operation failures → `.cocoa`.
    public var coarseKind: NebulaError.Kind { .cocoa }

    /// Bridges to a ``NebulaError`` under `kind`. The fine `code` is preserved as
    /// `metadata["MarklyCode"]`.
    public func toNebulaError(kind: NebulaError.Kind) -> NebulaError {
        var meta = metadata
        meta["MarklyCode"] = code
        return NebulaError(
            code: NebulaError.Code(domain: "Markly.MarklyRenderError", code: 0),
            kind: kind,
            message: message,
            metadata: meta,
            underlying: underlying
        )
    }
}