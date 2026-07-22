## Description

Briefly describe the change and why it is needed.

## Type of change

- [ ] Bug fix
- [ ] New feature
- [ ] Refactor
- [ ] Documentation
- [ ] Tests

## How has this been tested?

- [ ] `swift build` passes
- [ ] `swift test` passes
- [ ] Builds on iOS / macOS / tvOS / visionOS (`xcodebuild -scheme Markly -destination 'generic/platform=<iOS|tvOS|visionOS> Simulator' build`)
- [ ] Previews render correctly

## Checklist

- [ ] I kept the Domain (Foundation-only) / Rendering (SwiftUI) layer split
- [ ] I followed the Apple-only stack (`apple/swift-markdown` + Foundation `AttributedString`; no third-party markdown deps)
- [ ] I added or updated tests
- [ ] I gated platform-unavailable APIs (`#if !os(tvOS)` etc.) rather than leaving cross-platform gaps
- [ ] I updated `CHANGELOG.md`
- [ ] I updated `docs/Architecture.md` if the architecture changed