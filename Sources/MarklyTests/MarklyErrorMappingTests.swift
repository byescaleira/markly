//
//  MarklyErrorMappingTests.swift
//  Markly
//
//  Verifies Markly's layer errors (MarklySourceError / MarklyParseError / MarklyRenderError)
//  bridge into the closed `NebulaError.Kind` envelope correctly (coarse kind, MarklyCode
//  metadata, domain), that `NebulaError(error:)` dispatches a `NebulaFailure` through
//  `toNebulaError(kind: coarseKind)`, and that `Markly.defaultErrorConfiguration` resolves a
//  per-`MarklyCode` `NebulaUserError` with value-based recovery actions. Uses the explicit-
//  parameter DI path (constructing a `NebulaErrorConfiguration` directly) since configs are
//  NOT `Equatable` and the process-wide `NebulaErrorConfig.get()` is shared global state.
//

import XCTest
@testable import Markly
import Nebula

final class MarklyErrorMappingTests: XCTestCase {

    /// A Sendable reference box for recording handler invocations from `@Sendable` closures
    /// (a local `var` cannot be mutated from a concurrently-executing `@Sendable` closure
    /// under Swift 6; a `let` class reference can).
    private final class Box<T>: @unchecked Sendable { var value: T? }

    // MARK: - Layer-error bridging

    func testMarklySourceErrorBridgesToFileKindWithMarklyCode() {
        let err = MarklySourceError(code: "source-unavailable", message: "boom")
        let neb = err.toNebulaError(kind: err.coarseKind)
        XCTAssertEqual(neb.kind, .file)
        XCTAssertEqual(neb.metadata["MarklyCode"], "source-unavailable")
        XCTAssertEqual(neb.code.domain, "Markly.MarklySourceError")
        XCTAssertEqual(neb.message, "boom")
    }

    func testMarklyParseErrorBridgesToDecodingKindWithMarklyCode() {
        let err = MarklyParseError(code: "parse-failed", message: "bad md")
        let neb = err.toNebulaError(kind: err.coarseKind)
        XCTAssertEqual(neb.kind, .decoding)
        XCTAssertEqual(neb.metadata["MarklyCode"], "parse-failed")
        XCTAssertEqual(neb.code.domain, "Markly.MarklyParseError")
    }

    func testMarklyRenderErrorBridgesToCocoaKindWithMarklyCode() {
        let err = MarklyRenderError(code: "render-failed", message: "bad view")
        let neb = err.toNebulaError(kind: err.coarseKind)
        XCTAssertEqual(neb.kind, .cocoa)
        XCTAssertEqual(neb.metadata["MarklyCode"], "render-failed")
        XCTAssertEqual(neb.code.domain, "Markly.MarklyRenderError")
    }

    func testNebulaErrorInitFromMarklyFailureDispatchesViaCoarseKind() {
        // `NebulaError(error:)` dispatches a `NebulaFailure` through `toNebulaError(kind: coarseKind)`.
        let thrown = MarklyParseError(code: "parse-failed", message: "bad md")
        let neb = NebulaError(error: thrown)
        XCTAssertEqual(neb.kind, .decoding)
        XCTAssertEqual(neb.metadata["MarklyCode"], "parse-failed")
    }

    func testSourceErrorPreservesUnderlyingError() {
        let underlying = NebulaError(code: .init(domain: "test", code: 1), kind: .network, message: "net")
        let err = MarklySourceError(
            code: "source-unavailable",
            message: "boom",
            underlying: NebulaError.Box(underlying)
        )
        let neb = err.toNebulaError(kind: err.coarseKind)
        XCTAssertEqual(neb.underlying?.value.message, "net")
    }

    // MARK: - User-message mapping (Markly.defaultErrorConfiguration)

    func testDefaultConfigMapsSourceUnavailableToRetryDismiss() {
        let config = Markly.defaultErrorConfiguration
        let neb = MarklySourceError(code: "source-unavailable", message: "boom")
            .toNebulaError(kind: .file)
        let user = config.userError(for: neb)
        XCTAssertNotNil(user)
        XCTAssertEqual(user?.recoveryActions, [.retry, .dismiss])
    }

    func testDefaultConfigMapsParseFailedToDismiss() {
        let config = Markly.defaultErrorConfiguration
        let neb = MarklyParseError(code: "parse-failed", message: "bad md")
            .toNebulaError(kind: .decoding)
        let user = config.userError(for: neb)
        XCTAssertEqual(user?.recoveryActions, [.dismiss])
    }

    func testDefaultConfigFallsBackToNebulaDefaultForUnknownCode() {
        let config = Markly.defaultErrorConfiguration
        let neb = MarklySourceError(code: "some-other-code", message: "x")
            .toNebulaError(kind: .file)
        let user = config.userError(for: neb)
        // Unknown code → NebulaUserError.default(for: .file) → "Couldn't access the file.".
        XCTAssertEqual(user?.message, "Couldn't access the file.")
    }

    // MARK: - Report handler fires

    func testReportHandlerInvokedWithMarklyCategory() {
        let box = Box<NebulaErrorEvent>()
        let config = NebulaErrorConfiguration.default
            .withCategory("Markly")
            .withHandler { event in box.value = event }
        let neb = MarklyParseError(code: "parse-failed", message: "x")
            .toNebulaError(kind: .decoding)
        config.report(neb)
        XCTAssertEqual(box.value?.category, "Markly")
        XCTAssertEqual(box.value?.error.kind, .decoding)
        XCTAssertEqual(box.value?.error.metadata["MarklyCode"], "parse-failed")
    }

    func testReportIsGatedByIsEnabled() {
        let box = Box<NebulaErrorEvent>()
        let config = NebulaErrorConfiguration.default
            .withEnabled(false)
            .withHandler { event in box.value = event }
        config.report(MarklyParseError(code: "x", message: "y").toNebulaError(kind: .decoding))
        XCTAssertNil(box.value, "report should be suppressed when isEnabled is false")
    }

    // MARK: - RecoveryAction value semantics

    func testRecoveryActionsAreEquatable() {
        XCTAssertEqual(RecoveryAction.retry, .retry)
        XCTAssertEqual(RecoveryAction.custom("open"), .custom("open"))
        XCTAssertNotEqual(RecoveryAction.retry, .dismiss)
        XCTAssertNotEqual(RecoveryAction.custom("a"), .custom("b"))
    }
}