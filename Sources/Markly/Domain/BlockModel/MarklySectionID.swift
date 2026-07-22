//
//  MarklySectionID.swift
//  Markly
//
//  Stable, persistable per-block identity derived from document structure (a heading slug
//  like "h2-introduction", or a deterministic block index like "blk-0042"). Used for:
//    - Identity-based `ScrollPosition` restore (survives re-layout).
//    - Bookmark anchors.
//    - Table-of-contents deep-link targets.
//

import Foundation

/// A stable, persistable identifier for a single rendered block within a markdown document.
public struct MarklySectionID: Hashable, Sendable, Codable {
    /// The opaque raw identifier string (e.g. `"h2-introduction"` or `"blk-0042"`).
    public let raw: String

    /// Creates a section identifier from its raw string.
    public init(raw: String) {
        self.raw = raw
    }
}