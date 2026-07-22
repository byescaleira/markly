//
//  MarklyTableCell.swift
//  Markly
//
//  Table cell + column-alignment value types. Tables are parsed from swift-markdown's
//  `Table` and rendered by Markly's own SwiftUI table layout (Cosmos has no table atom).
//

import Foundation

/// Horizontal text alignment for a markdown table column.
public enum MarklyColumnAlignment: String, Sendable, Equatable, Codable {
    case left
    case right
    case center
}

/// A single cell in a markdown table: its inline content plus the column's alignment.
public struct MarklyTableCell: Sendable, Equatable, Codable {
    /// The inline content of the cell.
    public let inlines: [MarklyInline]
    /// The column alignment to apply when rendering this cell, if any.
    public let alignment: MarklyColumnAlignment?

    /// Creates a table cell.
    public init(inlines: [MarklyInline], alignment: MarklyColumnAlignment? = nil) {
        self.inlines = inlines
        self.alignment = alignment
    }
}