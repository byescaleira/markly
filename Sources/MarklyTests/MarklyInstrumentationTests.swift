//
//  MarklyInstrumentationTests.swift
//  Markly
//
//  Verifies the parse path is modeled as an instrumented `NebulaUseCase` and that the error-
//  reporting decorator routes failures through `NebulaErrorConfiguration.report(_:)` and
//  re-throws the original error. Logging via `.logged()`/`.instrumented()` writes to `os.Logger`
//  (the Nebula primary path, which does not fan out to a `NebulaLogConfiguration` handler), so
//  log-event capture is not asserted here — the secondary `NebulaLogConfig.get().log(_:_:)`
//  fan-out path is exercised directly in `testSecondaryLogPathFansOutToHandler`.
//

import Testing
@testable import Markly
import Nebula

@Suite struct MarklyInstrumentationTests {

    /// A Sendable reference box for recording handler invocations from `@Sendable` closures.
    private final class Box<T>: @unchecked Sendable { var value: T? }

    // MARK: - Instrumented parse use case

    @Test func parseUseCaseReturnsBlocksAndTOC() async throws {
        let output = try await MarklyParse.useCase.executeTyped(
            MarklyParseInput(source: "# Hi\n\nA paragraph.")
        )
        #expect(output.blocks.count == 2)
        #expect(output.tocEntries.first?.title == "Hi")
    }

    @Test func parseUseCaseExecuteTypedNarrowsToNebulaErrorOnSuccess() async throws {
        // The body is total today, so executeTyped succeeds (no NebulaError thrown).
        let output = try await MarklyParse.useCase.execute(MarklyParseInput(source: "# OK"))
        #expect(output.blocks.first?.id.raw == "h1-ok")
    }

    @Test func instrumentedCompositionDoesNotBreakParsingForLargerInput() async throws {
        let source = (0..<50).map { "# Heading \($0)\n\nBody \($0)." }.joined(separator: "\n\n")
        let output = try await MarklyParse.useCase.executeTyped(MarklyParseInput(source: source))
        #expect(output.blocks.count == 100, "50 headings + 50 paragraphs")
        #expect(output.tocEntries.count == 50)
    }

    // MARK: - Reported decorator

    @Test func reportedDecoratorReportsAndRethrowsOriginalError() async {
        let box = Box<NebulaError>()
        let errorConfig = NebulaErrorConfiguration.default
            .withHandler { event in box.value = event.error }
        let useCase = NebulaUseCase<MarklyParseInput, MarklyParseOutput>(
            name: "FailingParse",
            role: .query
        ) { _ in
            throw MarklyParseError(code: "forced", message: "forced failure")
        }
        .reported(using: errorConfig)

        do {
            _ = try await useCase.execute(MarklyParseInput(source: ""))
            Issue.record("Expected a throw")
        } catch {
            // Reported via the handler, then re-thrown as the original MarklyParseError.
            #expect(box.value != nil)
            #expect(box.value?.kind == .decoding)
            #expect(box.value?.metadata["MarklyCode"] == "forced")
            #expect(error is MarklyParseError, "reported() re-throws the original error")
        }
    }

    @Test func reportedDecoratorDoesNotReportOnSuccess() async throws {
        let box = Box<NebulaError>()
        let errorConfig = NebulaErrorConfiguration.default
            .withHandler { event in box.value = event.error }
        let useCase = NebulaUseCase<MarklyParseInput, MarklyParseOutput>(
            name: "OkParse",
            role: .query
        ) { input in
            MarklyParseOutput(blocks: MarklyDocumentParser.parse(input.source), tocEntries: [])
        }
        .reported(using: errorConfig)

        _ = try await useCase.execute(MarklyParseInput(source: "# Hi"))
        #expect(box.value == nil, "no report should fire on success")
    }

    // MARK: - Secondary log path fan-out (the path load() uses for explicit logging)

    @Test func secondaryLogPathFansOutToHandler() {
        let sink = NebulaMemoryLogHandler()
        let config = NebulaLogConfiguration.default
            .withSubsystem("com.markly.tests")
            .withHandler(sink.handler)
        // The secondary `log(_:_:)` path emits to os.Logger AND invokes the handler.
        config.log(.error, "Markly load failed: source-unavailable")
        let events = sink.snapshot()
        #expect(events.contains { $0.message.contains("source-unavailable") })
        #expect(events.last?.level == .error)
    }

    @Test func marklyConfigureInstallsMarklyCategoryAndSubsystem() {
        // Capture installed configs; restore a neutral default afterward so this test does not
        // leak process-wide state into other tests.
        let priorLog = NebulaLogConfig.get()
        let priorError = NebulaErrorConfig.get()
        defer {
            NebulaLogConfig.set(priorLog)
            NebulaErrorConfig.set(priorError)
        }

        Markly.configure(subsystem: "com.markly.tests.configure")

        let log = NebulaLogConfig.get()
        #expect(log.subsystem == "com.markly.tests.configure")
        #expect(log.category.rawValue == "Markly")

        let error = NebulaErrorConfig.get()
        #expect(error.category == "Markly")
    }
}