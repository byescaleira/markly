# Versioning — Markly

Markly follows [Semantic Versioning](https://semver.org). While below 1.0 (`0.x.y`) the rules are the relaxed pre-1.0 form: a **minor** (`0.x.0`) may add features *and* change behavior; a **patch** (`0.x.y`) is a backwards-compatible fix. Above 1.0 the standard semver guarantees apply.

## Version scheme

- **Patch** (`0.x.y`): bug fixes, no behavior change.
- **Minor** (`0.x.0`): additive features, new reader surfaces, non-breaking changes. May also adjust behavior while below 1.0.
- **Major** (`1.0.0` and beyond): the first stable API guarantee; thereafter breaking changes bump the major.

The version is a single source of truth: the `Markly.version` constant in `Sources/Markly/Markly.swift`, the `.package(url:…, from: "X.Y.Z")` line in this README, the `CHANGELOG.md` entry, and the git tag `X.Y.Z` are all bumped together at release time. The version is **not** stored in `Package.swift`.

## Deployment floor is independent

Markly targets Apple OS **26** across iOS / macOS / tvOS / visionOS (no watchOS). The deployment floor is declared in `Package.swift` (`platforms:`) and is tracked **separately** from the package version — bumping the OS floor is a deliberate, documented decision (see `docs/Architecture.md` §1), not an automatic consequence of the semver number.

## Deprecation runway

1. Mark a public API `@available(*, deprecated, message: "Use <replacement>; removed in Markly <N>.")`.
2. Keep it working for at least one minor release.
3. Remove (or mark `obsoleted:`) at the next minor/major.

## Changelog

Every release records changes under [Keep a Changelog](https://keepachangelog.com)-style sections in `CHANGELOG.md`.