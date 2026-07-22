//
//  MarklyReader.swift
//  Markly
//
//  The single entry point a host app uses. Wires the Cosmos environment (theme observable +
//  configuration + open-URL routing), parses the book's markdown via swift-markdown, and
//  presents the reading surface. With no controller and default configuration, a host app
//  renders a markdown document with one call:
//
//    import Markly
//    MarklyReader(book: MarklyLiteralBook(title: "Demo", markdown: "# Hello"))
//
//  See docs/Architecture.md §4 for the full public API surface.
//

import SwiftUI
import Cosmos
import Nebula

/// A markdown e-reader view. The primary public entry point of Markly.
public struct MarklyReader: View {
    private let book: any MarklyBook

    @State private var controller: MarklyReaderController
    @State private var blocks: [MarklyBlock] = []
    @State private var tocEntries: [MarklyTOCEntry] = []
    @State private var loaded = false
    @State private var loadFailed = false
    @State private var showReaderSheet = false
    @State private var readerSheetTab: MarklyReaderSheet.Tab = .contents
    @State private var showSettings = false
    @State private var showSearch = false
    /// The paragraph text selection the reader is currently holding (section id + character range),
    /// captured by the selectable text view's selection observer. Surfaced as the highlight color
    /// toolbar; `nil` when nothing is selected.
    @State private var pendingSelection: (section: MarklySectionID, range: Range<Int>)?

    @Environment(\.colorScheme) private var colorScheme
    /// A user-facing error value resolved through the process-wide `NebulaErrorConfiguration`
    /// when a load fails. `nil` unless `Markly.configure()` (or a custom config) maps the
    /// reported `MarklySourceError` to a `NebulaUserError`; the reader always shows its own
    /// localized title regardless, and renders the value-based recovery actions as buttons.
    @State private var userError: NebulaUserError?

    /// Creates a reader for a book.
    public init(
        book: any MarklyBook,
        configuration: MarklyConfiguration = .default,
        controller: MarklyReaderController? = nil
    ) {
        self.book = book
        self._controller = State(
            initialValue: controller ?? MarklyReaderController(book: book, configuration: configuration)
        )
    }

    public var body: some View {
        Group {
            if !loaded {
                CosmosProgress()
                    .frame(width: 32, height: 32)
            } else if loadFailed {
                VStack(spacing: CosmosSpacingTokens.medium) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 32))
                        .foregroundStyle(themeColors.error)
                    Text("Unable to load this book.", bundle: .module)
                        .foregroundStyle(themeColors.primary)
                    // Actionable recovery buttons from the resolved `NebulaUserError`, if any.
                    // The inline reader surface only meaningfully supports retry-style actions
                    // (there is no modal to cancel/dismiss), so `.cancel`/`.dismiss` are skipped
                    // and a localized "Try Again" fallback is always offered. Without a configured
                    // map, `userError` is nil and only the fallback shows.
                    ForEach(actionableRecoveryButtons, id: \.self) { action in
                        recoveryButton(for: action)
                    }
                    if !hasRetryAction {
                        Button {
                            Task { await load() }
                        } label: {
                            Text("Try Again", bundle: .module)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if blocks.isEmpty {
                Text("This book is empty.", bundle: .module)
                    .foregroundStyle(themeColors.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                NavigationStack {
                    MarklyReaderView(
                        blocks: blocks,
                        scrollRequest: controller.scrollRequest,
                        readingMode: controller.configuration.readingMode
                    )
                    // The current chapter (or book) title in the top bar. `.navigationTitle` is
                    // cross-platform (iOS nav bar, macOS window title, visionOS); `.inline` keeps
                    // it on one line in the iOS nav bar.
                    .navigationTitle(controller.principalTitle(for: book))
                    .toolbarTitleDisplayMode(.inline)
                    // The trailing overflow (⋯) menu — the one toolbar placement that is available
                    // everywhere (`primaryAction`). It holds contents, search, bookmarks,
                    // highlights, appearance, and chapter navigation; on tvOS (which has no bottom
                    // bar) it is the sole access point for every feature.
                    .toolbar {
                        ToolbarItem(placement: .primaryAction) {
                            overflowMenu
                        }
                    }
                    // The bottom quick-action bar (Contents / aA / Highlights / Share). Rendered as a
                    // `safeAreaInset` bar rather than a `.bottomBar` toolbar placement, which is iOS-
                    // only — this way the bar renders identically on iOS, macOS, and visionOS. tvOS
                    // reaches these features through the overflow menu instead.
                    #if !os(tvOS)
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        bottomBar
                            .background(themeColors.surface)
                    }
                    #endif
                }
            }
        }
        // Re-run when the book changes (id is the book's UUID): cancels the prior load and starts
        // a fresh one, so swapping `book` re-parses instead of leaving the previous book on screen.
        .task(id: book.id) { await load() }
        // Inject Cosmos: the live theme observable (for atoms that read it by type) and the
        // immutable theme @Entry value (for atoms that read it). The host's `cosmosConfiguration`
        // is intentionally NOT overridden here so a host's Cosmos-level config (tracking, motion,
        // accessibility, …) propagates into the reader subtree.
        .environment(controller.themeObservable)
        .environment(\.cosmosTheme, controller.themeObservable.theme)
        // Heading-on-appear reports the current section back to the controller (TOC highlight +
        // reading-position tracking). No-op unless the reader injects it (it always does here).
        .environment(\.marklySectionObserver) { id in
            controller.currentSectionID = id
        }
        // v0.3 feature plumbing into the block renderer: feature toggles (selectable paragraphs),
        // the current font-size step (drives the text view's font scaling), a per-section highlight
        // lookup (renders existing highlight backgrounds inline), and a selection observer the
        // selectable text view reports the user's drag selection to.
        .environment(\.marklyReaderFeatures, controller.configuration.features)
        .environment(\.marklyReaderFontSize, controller.configuration.fontSize)
        .environment(\.marklyHighlightsProvider) { id in
            controller.highlights(for: id)
        }
        .environment(\.marklySelectionObserver) { id, range in
            if let range {
                pendingSelection = (id, range)
            } else {
                pendingSelection = nil
            }
        }
        .cosmosOpenURL(inApp: controller.configuration.openURLInApp)
        // Debounced reading-position save: each time the current section changes, wait a beat
        // (cancelled by the next change, so only the settled section is saved) then persist it.
        .task(id: controller.currentSectionID) {
            guard controller.currentSectionID != nil else { return }
            try? await Task.sleep(for: .seconds(1.5))
            await controller.saveCurrentPosition()
        }
        // Persist the final position when the reader leaves the hierarchy (covers termination
        // that the debounced task — cancelled on disappear — would miss).
        .onDisappear {
            Task { await controller.saveCurrentPosition() }
        }
        // Re-resolve the effective theme when the system appearance flips (so `.auto` paper style
        // follows dark/light live).
        .onChange(of: colorScheme) { _, newValue in
            controller.resolveAndUpdateTheme(colorScheme: newValue)
        }
        // Brightness dimmer: a translucent black overlay whose opacity tracks the reader's
        // brightness setting (1.0 = full, lower = dimmer). Non-interactive and hidden from
        // VoiceOver so it never blocks the reading surface. tvOS manages brightness at the system
        // level, so it is omitted there.
        #if !os(tvOS)
        .overlay {
            Color.black
                .opacity(1 - controller.configuration.brightness)
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        #endif
        // Highlight color/note/remove bar, shown above the bottom toolbar while a text selection is
        // active. Only where text selection exists (never on tvOS).
        #if !os(tvOS)
        .overlay(alignment: .bottom) {
            if let pending = pendingSelection {
                MarklyHighlightToolbar(
                    controller: controller,
                    section: pending.section,
                    range: pending.range,
                    onDismiss: { pendingSelection = nil }
                )
                .padding(.horizontal, CosmosSpacingTokens.medium)
                .padding(.bottom, CosmosSpacingTokens.xl)
            }
        }
        #endif
        .sheet(isPresented: $showReaderSheet) {
            MarklyReaderSheet(
                entries: tocEntries,
                bookmarks: controller.bookmarks,
                highlights: controller.highlights,
                highlightExcerpt: highlightExcerpt(for:),
                currentID: controller.currentSectionID,
                initialTab: readerSheetTab,
                onSelectSection: { id in
                    controller.scrollTo(id)
                    showReaderSheet = false
                },
                onDeleteBookmark: { id in
                    Task { await controller.removeBookmark(id) }
                },
                onDeleteHighlight: { id in
                    Task { await controller.removeHighlight(id) }
                }
            )
        }
        .sheet(isPresented: $showSettings) {
            MarklySettingsSheet(controller: controller, colorScheme: colorScheme)
        }
        .sheet(isPresented: $showSearch) {
            MarklySearchView(blocks: blocks) { id in
                controller.scrollTo(id)
                showSearch = false
            }
        }
    }

    /// Shortcut to the controller's theme colors for the toolbar/error/empty states.
    private var themeColors: CosmosColorTokens { controller.themeObservable.theme.colors }

    // MARK: - Toolbar builders

    /// The overflow (⋯) menu in the top-trailing of the nav bar: contents, search, bookmarks,
    /// highlights, appearance, and chapter navigation. On tvOS (which has no bottom bar) this is
    /// the primary access point for every feature; elsewhere it complements the bottom bar.
    @ViewBuilder
    private var overflowMenu: some View {
        Menu {
            if controller.configuration.features.tableOfContents && !tocEntries.isEmpty {
                Button {
                    readerSheetTab = .contents
                    showReaderSheet = true
                } label: {
                    Label { Text("Contents", bundle: .module) } icon: { Image(systemName: "list.bullet.indent") }
                }
            }
            if controller.configuration.features.search && !blocks.isEmpty {
                Button {
                    showSearch = true
                } label: {
                    Label { Text("Search", bundle: .module) } icon: { Image(systemName: "magnifyingglass") }
                }
            }
            if controller.configuration.features.bookmarks {
                Button {
                    readerSheetTab = .bookmarks
                    showReaderSheet = true
                } label: {
                    Label { Text("Bookmarks", bundle: .module) } icon: { Image(systemName: "bookmark") }
                }
            }
            if controller.configuration.features.highlights {
                Button {
                    readerSheetTab = .highlights
                    showReaderSheet = true
                } label: {
                    Label { Text("Highlights", bundle: .module) } icon: { Image(systemName: "highlighter") }
                }
            }
            if controller.configuration.features.settingsPanel {
                Button {
                    showSettings = true
                } label: {
                    Label { Text("Appearance", bundle: .module) } icon: { Image(systemName: "textformat") }
                }
            }
            if controller.configuration.features.chapters && !controller.chapters.isEmpty {
                Section {
                    Button {
                        controller.goToPreviousChapter()
                    } label: {
                        Label { Text("Previous Chapter", bundle: .module) } icon: { Image(systemName: "chevron.up") }
                    }
                    Button {
                        controller.goToNextChapter()
                    } label: {
                        Label { Text("Next Chapter", bundle: .module) } icon: { Image(systemName: "chevron.down") }
                    }
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel(Text("Reader Menu", bundle: .module))
    }

    /// The bottom quick-action bar (Contents / aA / Highlights / Share), gated per feature. Drawn
    /// as a `safeAreaInset` bar (not a `.bottomBar` toolbar placement, which is iOS-only) so it
    /// renders on iOS, macOS, and visionOS alike. tvOS reaches these through `overflowMenu`.
    @ViewBuilder
    private var bottomBar: some View {
        HStack(spacing: 0) {
            if controller.configuration.features.tableOfContents && !tocEntries.isEmpty {
                bottomBarButton(systemName: "list.bullet.indent", label: "Contents") {
                    readerSheetTab = .contents
                    showReaderSheet = true
                }
            }
            if controller.configuration.features.settingsPanel {
                bottomBarButton(systemName: "textformat", label: "Appearance") {
                    showSettings = true
                }
            }
            if controller.configuration.features.highlights {
                bottomBarButton(systemName: "highlighter", label: "Highlights") {
                    readerSheetTab = .highlights
                    showReaderSheet = true
                }
            }
            Spacer(minLength: 0)
            #if !os(tvOS)
            if controller.configuration.features.share {
                ShareLink(item: sharePayload) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 20))
                        .foregroundStyle(themeColors.primary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .accessibilityLabel(Text("Share", bundle: .module))
            }
            #endif
        }
        .padding(.horizontal, CosmosSpacingTokens.medium)
        .padding(.vertical, CosmosSpacingTokens.small)
    }

    /// A single evenly-spaced bottom-bar button with a localized accessibility label.
    @ViewBuilder
    private func bottomBarButton(systemName: String, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 20))
                .foregroundStyle(themeColors.primary)
                .frame(maxWidth: .infinity)
        }
        .accessibilityLabel(Text(label, bundle: .module))
    }

    // MARK: - Highlight excerpts + share

    /// The plain-text excerpt of a highlight (its range within its section's flattened text), for
    /// the Highlights list. Returns an empty string if the section can't be located.
    private func highlightExcerpt(for highlight: MarklyHighlight) -> String {
        guard let block = findBlock(id: highlight.sectionID, in: blocks),
              let plain = plainText(for: block) else { return "" }
        let lower = min(max(0, highlight.range.lowerBound), plain.count)
        let upper = min(max(lower, highlight.range.upperBound), plain.count)
        let start = plain.index(plain.startIndex, offsetBy: lower)
        let end = plain.index(plain.startIndex, offsetBy: upper)
        return String(plain[start..<end])
    }

    /// The text payload shared by the bottom-bar Share button: the book title plus its first
    /// non-empty paragraph (an excerpt rather than the whole book, since `book.source()` is async
    /// and the full markdown can be large).
    private var sharePayload: String {
        for block in blocks {
            if case .paragraph(let inlines, _) = block {
                let plain = inlinePlainText(inlines)
                if !plain.isEmpty { return "\(book.title)\n\n\(plain)" }
            }
        }
        return book.title
    }

    /// Recursively finds a block by section id (highlights may anchor to nested blocks).
    private func findBlock(id: MarklySectionID, in blocks: [MarklyBlock]) -> MarklyBlock? {
        for block in blocks {
            if block.id == id { return block }
            switch block {
            case .blockQuote(let inner, _):
                if let found = findBlock(id: id, in: inner) { return found }
            case .blockDirective(_, _, let inner, _):
                if let found = findBlock(id: id, in: inner) { return found }
            case .list(_, _, let items, _):
                for item in items {
                    if let found = findBlock(id: id, in: item) { return found }
                }
            default:
                break
            }
        }
        return nil
    }

    /// The flattened plain text of a text-bearing block (paragraph or heading), or `nil` for
    /// non-text blocks (highlights only anchor to selectable paragraphs in practice).
    private func plainText(for block: MarklyBlock) -> String? {
        switch block {
        case .paragraph(let inlines, _), .heading(_, let inlines, _):
            return inlinePlainText(inlines)
        default:
            return nil
        }
    }

    @MainActor
    private func load() async {
        loaded = false
        blocks = []
        tocEntries = []
        loadFailed = false
        userError = nil
        controller.book = book
        controller.currentSectionID = nil
        do {
            let source = try await book.source()
            // Parse through the instrumented use case: `.instrumented()` logs start/ok/error,
            // measures, and reports any throw; the body detaches the CPU-bound parser off-main.
            let parsed = try await MarklyParse.useCase.executeTyped(MarklyParseInput(source: source))
            blocks = parsed.blocks
            tocEntries = parsed.tocEntries
            // Derive chapters (top-level `#` grouping) + the section→chapter index map, and load
            // this book's bookmarks, highlights, and saved reading position.
            controller.setChapters(
                MarklyChapters.entries(from: blocks),
                sectionMap: MarklyChapters.indexMap(from: blocks)
            )
            await controller.refreshBookmarks()
            await controller.refreshHighlights()
            if let saved = await controller.restorePosition() {
                controller.scrollTo(saved)
            }
            // Resolve the effective theme for the current paper style + system appearance (so `.auto`
            // follows the system) and push it to the live theme observable.
            controller.resolveAndUpdateTheme(colorScheme: colorScheme)
        } catch {
            // `book.source()` failed (the parse body is total today, so this is the source path).
            // Wrap as a `MarklySourceError`, report it through the process-wide config, resolve a
            // value-based user error (recovery actions), and log it under Markly's category.
            let marklyError = MarklySourceError(
                code: "source-unavailable",
                message: "Could not load “\(book.title)”.",
                underlying: NebulaError.Box(NebulaError(error: error))
            )
            let nebula = marklyError.toNebulaError(kind: marklyError.coarseKind)
            NebulaErrorConfig.report(nebula)
            userError = NebulaErrorConfig.userError(for: nebula)
            NebulaLogConfig.get().log(.error, "Markly load failed: \(marklyError.code) — \(marklyError.message)")
            loadFailed = true
        }
        loaded = true
    }

    /// The recovery actions worth rendering on the inline failure surface — `.retry` and any
    /// app-defined `.custom` actions. `.cancel`/`.dismiss` are skipped because the inline reader
    /// has no modal to dismiss.
    private var actionableRecoveryButtons: [RecoveryAction] {
        (userError?.recoveryActions ?? []).filter { action in
            switch action {
            case .retry, .custom: return true
            default: return false
            }
        }
    }

    /// `true` when the resolved user error already offers a `.retry` action (so the localized
    /// "Try Again" fallback can be suppressed to avoid a duplicate).
    private var hasRetryAction: Bool {
        (userError?.recoveryActions ?? []).contains(.retry)
    }

    /// Renders a recovery-action button. `.retry` and `.custom` re-run `load()` (a custom action
    /// is host-defined; without a dispatch table, retry is the only meaningful interpretation an
    /// e-reader can give it inline).
    @ViewBuilder
    private func recoveryButton(for action: RecoveryAction) -> some View {
        switch action {
        case .retry:
            Button {
                Task { await load() }
            } label: {
                Text("Try Again", bundle: .module)
            }
        case .custom(let label):
            Button {
                Task { await load() }
            } label: {
                Text(verbatim: label)
            }
        case .cancel, .dismiss:
            // Not rendered on the inline surface (see `actionableRecoveryButtons`).
            EmptyView()
        }
    }
}

// MARK: - Preview

#Preview {
    MarklyReader(
        book: MarklyLiteralBook(
            title: "Sampler",
            markdown: """
            # The Markly Sampler

            A paragraph with **bold**, *italic*, ~~struck~~, `code`, and a [link](https://example.com).

            ## Code

            ```swift
            let x = 42
            ```

            ## List

            1. First
            2. Second
               - Nested
            3. Third

            > A block quote with *emphasis*.

            ---

            | A | B |
            |:--|:-:|
            | 1 | 2 |
            """
        ),
        configuration: .default
    )
}