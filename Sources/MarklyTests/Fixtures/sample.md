# The Markly Sampler

A short markdown document exercising every block the parser must handle, used as a fixture
for parse/render round-trip tests and `#Preview` content.

## Inline styles

This paragraph has **bold**, *italic*, ~~struck~~, and `inline code` runs, plus an
[external link](https://swiftlang.github.io/swift-markdown/) and a hard
line break right here.
The next line continues after a soft break.

## A code block

```swift
import Markdown

let document = Document(parsing: "# Hello")
```

## A list

1. Ordered first
2. Ordered second
   - Nested bullet
   - Another nested bullet
3. Ordered third

## A quote and a rule

> A block quote with *emphasis*.

---

## A table

| Feature      | Status | Notes            |
|:-------------|:-----:|:-----------------|
| Headings     | Yes    | levels 1–6       |
| Lists        | Yes    | ordered + nested |
| Tables       | Yes    | with alignment   |