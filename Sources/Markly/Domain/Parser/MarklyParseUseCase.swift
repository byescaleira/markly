//
//  MarklyParseUseCase.swift
//  Markly
//
//  The parse operation modeled as a `NebulaUseCase` so `.instrumented()` wires logging +
//  measurement + error reporting around it for free (the canonical Nebula adoption pattern:
//  `reported().measured().logged()`). The body is `@Sendable` and captures only the stateless
//  parser, so the value is safe to share across the load `Task`. Parsing runs off the main
//  actor inside the body so `.measured()` times the real CPU cost and the UI stays responsive.
//
//  Constructed lazily (a `static let` on `MarklyParse`), so it resolves the process-wide
//  `NebulaLogConfig`/`NebulaMeasureConfiguration`/`NebulaErrorConfiguration` on first use —
//  call `Markly.configure()` before constructing a `MarklyReader` to install Markly's
//  subsystem/user-message map (see MarklyErrorConfig.swift).
//

import Foundation
import Nebula

/// Input DTO for the parse use case: the raw markdown source.
public struct MarklyParseInput: NebulaDTO, Equatable, Sendable {
    /// The raw markdown source to parse.
    public let source: String

    /// Creates the input.
    public init(source: String) { self.source = source }
}

/// Output DTO for the parse use case: the parsed block model and its derived table of contents.
public struct MarklyParseOutput: NebulaDTO, Equatable, Sendable {
    /// The parsed blocks.
    public let blocks: [MarklyBlock]
    /// The table-of-contents entries derived from the blocks.
    public let tocEntries: [MarklyTOCEntry]

    /// Creates the output.
    public init(blocks: [MarklyBlock], tocEntries: [MarklyTOCEntry]) {
        self.blocks = blocks
        self.tocEntries = tocEntries
    }
}

/// The parse operation as an instrumented `NebulaUseCase`.
public enum MarklyParse {

    /// The instrumented parse use case. `.instrumented()` composes
    /// `reported().measured().logged()` (logged outermost), so each parse emits start/ok/error
    /// logs, a signpost-friendly measurement, and an error report if the body ever throws.
    /// The body is a query (parsing is non-mutating — CQS) and detaches the CPU-bound parser.
    public static let useCase: NebulaUseCase<MarklyParseInput, MarklyParseOutput> = {
        NebulaUseCase<MarklyParseInput, MarklyParseOutput>(
            name: "Markly.Parse",
            role: .query
        ) { input in
            // Detach inside the body so .measured() times the real off-main cost. swift-markdown
            // is total today (this body does not throw), but .reported() is wired regardless.
            let blocks = await Task.detached(priority: .userInitiated) {
                MarklyDocumentParser.parse(input.source)
            }.value
            return MarklyParseOutput(blocks: blocks, tocEntries: MarklyTOC.entries(from: blocks))
        }
        .instrumented()
    }()
}