//
//  MarklyHighlightToolbar.swift
//  Markly
//
//  The floating highlight action bar shown above the bottom toolbar when the user has an active
//  text selection (Apple Books' select-then-color flow). Tapping a color either creates a new
//  highlight over the selection (using that color and making it the sticky color) or, if a
//  highlight already covers that exact range, recolors it. The bar also offers a note editor and
//  delete. Shown only where text selection exists (iOS/iPadOS/visionOS/macOS) — never on tvOS.
//  See docs/Architecture.md §9.
//

import SwiftUI
import Cosmos

/// The highlight color/note/remove action bar for an active text selection.
struct MarklyHighlightToolbar: View {
    @Bindable var controller: MarklyReaderController
    let section: MarklySectionID
    let range: Range<Int>
    /// Called to clear the selection (hides the bar).
    let onDismiss: () -> Void

    @Environment(\.cosmosTheme) private var theme
    @State private var noteText: String = ""
    @State private var showNote = false

    /// The existing highlight covering exactly this selection, if any (edit mode vs create mode).
    private var existing: MarklyHighlight? {
        controller.highlights(for: section).first { $0.range == range }
    }

    var body: some View {
        HStack(spacing: CosmosSpacingTokens.medium) {
            ForEach(MarklyHighlightColor.markerColors) { color in
                colorButton(color)
            }
            // Underline style.
            colorButton(.underline)
            CosmosDivider()
                .frame(height: 24)
            noteButton
            if existing != nil {
                removeButton
            }
        }
        .padding(.horizontal, CosmosSpacingTokens.medium)
        .padding(.vertical, CosmosSpacingTokens.small)
        // Large floating surface → iOS 26 Liquid Glass. `.glassEffect` is unavailable on visionOS
        // (see SwiftUICore availability), so visionOS falls back to the translucent surface card.
        #if os(visionOS)
        .background(theme.colors.surface, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 8, y: 2)
        #else
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
        #endif
        .task(id: existing?.id) {
            // Seed the note editor with the existing highlight's note whenever the highlight changes.
            noteText = existing?.note ?? ""
        }
        .sheet(isPresented: $showNote) {
            noteSheet
        }
    }

    // MARK: Color / underline

    @ViewBuilder
    private func colorButton(_ color: MarklyHighlightColor) -> some View {
        let isSelected = existing?.color == color
        Button {
            applyColor(color)
        } label: {
            Group {
                if color.isUnderline {
                    Image(systemName: "underline")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(theme.colors.primary)
                } else {
                    Circle()
                        .fill(color.color)
                }
            }
            .frame(width: 28, height: 28)
            .overlay {
                if isSelected {
                    Circle()
                        .stroke(theme.colors.primary, lineWidth: 2)
                }
            }
            .accessibilityLabel(Text(color.accessibilityName, bundle: .module))
        }
        .buttonStyle(.plain)
    }

    private func applyColor(_ color: MarklyHighlightColor) {
        Task { @MainActor in
            if let existing {
                await controller.setHighlightColor(color, for: existing.id)
            } else {
                controller.setLastHighlightColor(color)
                _ = await controller.addHighlight(at: section, range: range)
            }
        }
    }

    // MARK: Note

    private var noteButton: some View {
        Button {
            showNote = true
        } label: {
            Image(systemName: existing?.note?.isEmpty == false ? "note.text" : "square.and.pencil")
                .font(.system(size: 18))
                .foregroundStyle(theme.colors.primary)
                .frame(width: 28, height: 28)
                .accessibilityLabel(Text("Note", bundle: .module))
        }
        .buttonStyle(.plain)
        // Note is available even on a fresh selection (no highlight yet): the save path creates a
        // highlight with the sticky color and attaches the note. Mirrors Apple Books, which lets a
        // user add a note directly to a new selection rather than forcing a color tap first.
    }

    private var noteSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: CosmosSpacingTokens.medium) {
                CosmosTextField(
                    verbatim: "Note",
                    text: $noteText,
                    prompt: Text("Add a note…", bundle: .module),
                    axis: .vertical
                )
            }
            .padding(CosmosSpacingTokens.medium)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.colors.background)
            .navigationTitle(Text("Note", bundle: .module))
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        let trimmed = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
                        Task { @MainActor in
                            if let existing {
                                await controller.setHighlightNote(trimmed.isEmpty ? nil : trimmed, for: existing.id)
                            } else if !trimmed.isEmpty {
                                // Fresh selection: create a highlight with the sticky color, then
                                // attach the note. (An empty note creates nothing — tapping Save on
                                // a blank editor is a no-op rather than an empty highlight.)
                                let created = await controller.addHighlight(at: section, range: range)
                                await controller.setHighlightNote(trimmed, for: created.id)
                            }
                        }
                        showNote = false
                    } label: {
                        Text("Save", bundle: .module)
                    }
                }
            }
        }
        .presentationDetents([.fraction(0.35), .medium])
    }

    // MARK: Remove

    private var removeButton: some View {
        Button {
            Task { @MainActor in
                if let existing {
                    await controller.removeHighlight(existing.id)
                    onDismiss()
                }
            }
        } label: {
            Image(systemName: "trash")
                .font(.system(size: 18))
                .foregroundStyle(theme.colors.error)
                .frame(width: 28, height: 28)
                .accessibilityLabel(Text("Remove Highlight", bundle: .module))
        }
        .buttonStyle(.plain)
    }
}