import Foundation
// `SwiftUIAttributes` (used as a stored property of `MarkdownUIAttributes` below) is re-exported by
// `SwiftUI`; importing it surfaces it without the OS 26 "cannot use struct 'SwiftUIAttributes' ...
// 'SwiftUICore' was not imported by this file" warning (`SwiftUICore` is an implementation detail
// of `SwiftUI` on this toolchain, so it can't be imported directly).
import SwiftUI

enum FontPropertiesAttribute: AttributedStringKey {
  typealias Value = FontProperties
  static let name = "fontProperties"
}

extension AttributeScopes {
  var markdownUI: MarkdownUIAttributes.Type {
    MarkdownUIAttributes.self
  }

  struct MarkdownUIAttributes: AttributeScope {
    let swiftUI: SwiftUIAttributes
    let fontProperties: FontPropertiesAttribute
  }
}

extension AttributeDynamicLookup {
  subscript<T: AttributedStringKey>(
    dynamicMember keyPath: KeyPath<AttributeScopes.MarkdownUIAttributes, T>
  ) -> T {
    return self[T.self]
  }
}

extension AttributedString {
  func resolvingFonts() -> AttributedString {
    var output = self

    for run in output.runs {
      guard let fontProperties = run.fontProperties else {
        continue
      }
      output[run.range].font = .withProperties(fontProperties)
      output[run.range].fontProperties = nil
    }

    return output
  }
}
