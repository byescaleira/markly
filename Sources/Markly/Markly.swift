//
//  Markly.swift
//  Markly
//
//  Umbrella namespace + package version. Mirrors the shape of the sibling `Nebula` and
//  `Cosmos` packages. The version is a plain string rather than a shared `*Version` type so
//  Markly does not couple its public surface to either sibling's version representation.
//

import Foundation

/// Namespace for the Markly markdown e-reader package.
public enum Markly {
    /// Semantic version of the Markly package.
    public static let version = "0.5.0"
}