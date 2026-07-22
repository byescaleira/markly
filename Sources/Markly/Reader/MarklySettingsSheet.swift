//
//  MarklySettingsSheet.swift
//  Markly
//
//  The "aA" appearance sheet (Apple Books' Themes & Settings panel): font size, brightness, paper
//  style, and reading mode. Every change is pushed straight through `MarklyReaderController` (which
//  persists it and, for paper style, re-resolves the live theme), so the reader updates live as the
//  user drags. Styled from Cosmos theme tokens. Presented as a sheet from the bottom toolbar's aA
//  button. See docs/Architecture.md §6, §8.
//

import SwiftUI
import Cosmos

/// The appearance / settings sheet (font size, brightness, paper style, reading mode).
struct MarklySettingsSheet: View {
    @Bindable var controller: MarklyReaderController
    let colorScheme: ColorScheme

    @Environment(\.cosmosTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: CosmosSpacingTokens.large) {
                    fontSizeSection
                    #if !os(tvOS)
                    brightnessSection
                    #endif
                    paperStyleSection
                    readingModeSection
                }
                .padding(CosmosSpacingTokens.medium)
            }
            .background(theme.colors.background)
            .navigationTitle(Text("Appearance", bundle: .module))
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Done", bundle: .module)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: Font size

    private var fontSizeSection: some View {
        VStack(alignment: .leading, spacing: CosmosSpacingTokens.small) {
            Text("Font Size", bundle: .module)
                .font(theme.typography.font(for: .headline))
                .foregroundStyle(theme.colors.primary)

            fontSizeControl
        }
    }

    /// The font-size control. `Slider` (and `Stepper`) are unavailable on tvOS, so there a
    /// `Picker` over the discrete steps is used instead; elsewhere the Apple-Books-style small-A /
    /// large-A slider drives the same discrete binding.
    @ViewBuilder
    private var fontSizeControl: some View {
        #if os(tvOS)
        Picker("Font Size", selection: Binding(
            get: { controller.configuration.fontSize },
            set: { controller.setFontSize($0) }
        )) {
            ForEach(MarklyFontSize.allCases) { size in
                Text(verbatim: size.stepLabel).tag(size)
            }
        }
        #else
        HStack(spacing: CosmosSpacingTokens.medium) {
            Text(verbatim: "A")
                .font(.system(size: 14))
                .foregroundStyle(theme.colors.secondary)
            Slider(
                value: fontSizeBinding,
                in: 0...Double(MarklyFontSize.allCases.count - 1),
                step: 1
            )
            // The "Font Size" label is a sibling Text, not tied to this Slider, so VoiceOver
            // would announce only "slider" — attach the setting name explicitly.
            .accessibilityLabel(Text("Font Size", bundle: .module))
            .tint(theme.colors.accent)
            Text(verbatim: "A")
                .font(.system(size: 26))
                .foregroundStyle(theme.colors.secondary)
        }
        #endif
    }

    /// A discrete slider binding over the font-size steps (index ↔ `MarklyFontSize`).
    private var fontSizeBinding: Binding<Double> {
        Binding(
            get: { Double(MarklyFontSize.allCases.firstIndex(of: controller.configuration.fontSize) ?? 0) },
            set: { value in
                let index = min(MarklyFontSize.allCases.count - 1, max(0, Int(value.rounded())))
                controller.setFontSize(MarklyFontSize.allCases[index])
            }
        )
    }

    // MARK: Brightness

    #if !os(tvOS)
    private var brightnessSection: some View {
        VStack(alignment: .leading, spacing: CosmosSpacingTokens.small) {
            Text("Brightness", bundle: .module)
                .font(theme.typography.font(for: .headline))
                .foregroundStyle(theme.colors.primary)

            HStack(spacing: CosmosSpacingTokens.medium) {
                Image(systemName: "sun.min")
                    .foregroundStyle(theme.colors.secondary)
                Slider(
                    value: Binding(
                        get: { controller.configuration.brightness },
                        set: { controller.setBrightness($0) }
                    ),
                    in: 0.15...1.0
                )
                .accessibilityLabel(Text("Brightness", bundle: .module))
                .tint(theme.colors.accent)
                Image(systemName: "sun.max.fill")
                    .foregroundStyle(theme.colors.secondary)
            }
        }
    }
    #endif

    // MARK: Paper style

    private var paperStyleSection: some View {
        VStack(alignment: .leading, spacing: CosmosSpacingTokens.small) {
            Text("Paper Style", bundle: .module)
                .font(theme.typography.font(for: .headline))
                .foregroundStyle(theme.colors.primary)

            Picker("Paper Style", selection: paperStyleBinding) {
                ForEach(PaperStyle.allCases) { style in
                    Text(verbatim: style.displayName).tag(style)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var paperStyleBinding: Binding<PaperStyle> {
        Binding(
            get: { controller.configuration.paperStyle },
            set: { style in
                controller.setPaperStyle(style)
                controller.resolveAndUpdateTheme(colorScheme: colorScheme)
            }
        )
    }

    // MARK: Reading mode

    private var readingModeSection: some View {
        VStack(alignment: .leading, spacing: CosmosSpacingTokens.small) {
            Text("Reading Mode", bundle: .module)
                .font(theme.typography.font(for: .headline))
                .foregroundStyle(theme.colors.primary)

            Picker("Reading Mode", selection: readingModeBinding) {
                Text("Scroll", bundle: .module).tag(MarklyReadingMode.continuous)
                Text("Pages", bundle: .module).tag(MarklyReadingMode.paged)
            }
            .pickerStyle(.segmented)
        }
    }

    private var readingModeBinding: Binding<MarklyReadingMode> {
        Binding(
            get: { controller.configuration.readingMode },
            set: { controller.setReadingMode($0) }
        )
    }
}

extension PaperStyle {
    /// A short display name for the settings picker.
    fileprivate var displayName: String {
        switch self {
        case .auto: "Auto"
        case .white: "White"
        case .sepia: "Sepia"
        case .night: "Night"
        case .dark: "Dark"
        }
    }
}