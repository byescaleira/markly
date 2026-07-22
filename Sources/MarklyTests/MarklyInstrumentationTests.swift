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

import XCTest
@testable import Markly
import Nebula

final class MarklyInstrumentationTests: XCTestCase {

    /// A Sendable reference box for recording handler invocations from `@Sendable` closures.
    private final class Box<T>: @unchecked Sendable { var value: T? }

    // MARK: - Instrumented parse use case

    func testParseUseCaseReturnsBlocksAndTOC() async throws {
        let output = try await MarklyParse.useCase.executeTyped(
            MarklyParseInput(source: "# Hi\n\nA paragraph.")
        )
        XCTAssertEqual(output.blocks.count, 2)
        XCTAssertEqual(output.tocEntries.first?.title, "Hi")
    }

    func testParseUseCaseExecuteTypedNarrowsToNebulaErrorOnSuccess() async throws {
        // The body is total today, so executeTyped succeeds (no NebulaError thrown).
        let output = try await MarklyParse.useCase.execute(MarklyParseInput(source: "# OK"))
        XCTAssertEqual(output.blocks.first?.id.raw, "h1-ok")
    }

    func testInstrumentedCompositionDoesNotBreakParsingForLargerInput() async throws {
        let source = (0..<50).map { "# Heading \($0)\n\nBody \($0)." }.joined(separator: "\n\n")
        let output = try await MarklyParse.useCase.executeTyped(MarklyParseInput(source: source))
        XCTAssertEqual(output.blocks.count, 100, "50 headings + 50 paragraphs")
        XCTAssertEqual(output.tocEntries.count, 50)
    }

    // MARK: - Reported decorator

    func testReportedDecoratorReportsAndRethrowsOriginalError() async {
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
            XCTFail("Expected a throw")
        } catch {
            // Reported via the handler, then re-thrown as the original MarklyParseError.
            XCTAssertNotNil(box.value)
            XCTAssertEqual(box.value?.kind, .decoding)
            XCTAssertEqual(box.value?.metadata["MarklyCode"], "forced")
            XCTAssertTrue(error is MarklyParseError, "reported() re-throws the original error")
        }
    }

    func testReportedDecoratorDoesNotReportOnSuccess() async throws {
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
        XCTAssertNil(box.value, "no report should fire on success")
    }

    // MARK: - Secondary log path fan-out (the path load() uses for explicit logging)

    func testSecondaryLogPathFansOutToHandler() {
        let sink = NebulaMemoryLogHandler()
        let config = NebulaLogConfiguration.default
            .withSubsystem("com.markly.tests")
            .withHandler(sink.handler)
        // The secondary `log(_:_:)` path emits to os.Logger AND invokes the handler.
        config.log(.error, "Markly load failed: source-unavailable")
        let events = sink.snapshot()
        XCTAssertTrue(events.contains { $0.message.contains("source-unavailable") })
        XCTAssertEqual(events.last?.level, .error)
    }

    func testMarklyConfigureInstallsMarklyCategoryAndSubsystem() {
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
        XCTAssertEqual(log.subsystem, "com.markly.tests.configure")
        XCTAssertEqual(log.category.rawValue, "Markly")

        let error = NebulaErrorConfig.get()
        XCTAssertEqual(error.category, "Markly")
    }
}