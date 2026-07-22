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

import Testing
@testable import Markly
import Nebula

@Suite struct MarklyErrorMappingTests {

    /// A Sendable reference box for recording handler invocations from `@Sendable` closures
    /// (a local `var` cannot be mutated from a concurrently-executing `@Sendable` closure
    /// under Swift 6; a `let` class reference can).
    private final class Box<T>: @unchecked Sendable { var value: T? }

    // MARK: - Layer-error bridging

    @Test func marklySourceErrorBridgesToFileKindWithMarklyCode() {
        let err = MarklySourceError(code: "source-unavailable", message: "boom")
        let neb = err.toNebulaError(kind: err.coarseKind)
        #expect(neb.kind == .file)
        #expect(neb.metadata["MarklyCode"] == "source-unavailable")
        #expect(neb.code.domain == "Markly.MarklySourceError")
        #expect(neb.message == "boom")
    }

    @Test func marklyParseErrorBridgesToDecodingKindWithMarklyCode() {
        let err = MarklyParseError(code: "parse-failed", message: "bad md")
        let neb = err.toNebulaError(kind: err.coarseKind)
        #expect(neb.kind == .decoding)
        #expect(neb.metadata["MarklyCode"] == "parse-failed")
        #expect(neb.code.domain == "Markly.MarklyParseError")
    }

    @Test func marklyRenderErrorBridgesToCocoaKindWithMarklyCode() {
        let err = MarklyRenderError(code: "render-failed", message: "bad view")
        let neb = err.toNebulaError(kind: err.coarseKind)
        #expect(neb.kind == .cocoa)
        #expect(neb.metadata["MarklyCode"] == "render-failed")
        #expect(neb.code.domain == "Markly.MarklyRenderError")
    }

    @Test func nebulaErrorInitFromMarklyFailureDispatchesViaCoarseKind() {
        // `NebulaError(error:)` dispatches a `NebulaFailure` through `toNebulaError(kind: coarseKind)`.
        let thrown = MarklyParseError(code: "parse-failed", message: "bad md")
        let neb = NebulaError(error: thrown)
        #expect(neb.kind == .decoding)
        #expect(neb.metadata["MarklyCode"] == "parse-failed")
    }

    @Test func sourceErrorPreservesUnderlyingError() {
        let underlying = NebulaError(code: .init(domain: "test", code: 1), kind: .network, message: "net")
        let err = MarklySourceError(
            code: "source-unavailable",
            message: "boom",
            underlying: NebulaError.Box(underlying)
        )
        let neb = err.toNebulaError(kind: err.coarseKind)
        #expect(neb.underlying?.value.message == "net")
    }

    // MARK: - User-message mapping (Markly.defaultErrorConfiguration)

    @Test func defaultConfigMapsSourceUnavailableToRetryDismiss() {
        let config = Markly.defaultErrorConfiguration
        let neb = MarklySourceError(code: "source-unavailable", message: "boom")
            .toNebulaError(kind: .file)
        let user = config.userError(for: neb)
        #expect(user != nil)
        #expect(user?.recoveryActions == [.retry, .dismiss])
    }

    @Test func defaultConfigMapsParseFailedToDismiss() {
        let config = Markly.defaultErrorConfiguration
        let neb = MarklyParseError(code: "parse-failed", message: "bad md")
            .toNebulaError(kind: .decoding)
        let user = config.userError(for: neb)
        #expect(user?.recoveryActions == [.dismiss])
    }

    @Test func defaultConfigFallsBackToNebulaDefaultForUnknownCode() {
        let config = Markly.defaultErrorConfiguration
        let neb = MarklySourceError(code: "some-other-code", message: "x")
            .toNebulaError(kind: .file)
        let user = config.userError(for: neb)
        // Unknown code → NebulaUserError.default(for: .file) → "Couldn't access the file.".
        #expect(user?.message == "Couldn't access the file.")
    }

    // MARK: - Report handler fires

    @Test func reportHandlerInvokedWithMarklyCategory() {
        let box = Box<NebulaErrorEvent>()
        let config = NebulaErrorConfiguration.default
            .withCategory("Markly")
            .withHandler { event in box.value = event }
        let neb = MarklyParseError(code: "parse-failed", message: "x")
            .toNebulaError(kind: .decoding)
        config.report(neb)
        #expect(box.value?.category == "Markly")
        #expect(box.value?.error.kind == .decoding)
        #expect(box.value?.error.metadata["MarklyCode"] == "parse-failed")
    }

    @Test func reportIsGatedByIsEnabled() {
        let box = Box<NebulaErrorEvent>()
        let config = NebulaErrorConfiguration.default
            .withEnabled(false)
            .withHandler { event in box.value = event }
        config.report(MarklyParseError(code: "x", message: "y").toNebulaError(kind: .decoding))
        #expect(box.value == nil, "report should be suppressed when isEnabled is false")
    }

    // MARK: - RecoveryAction value semantics

    @Test func recoveryActionsAreEquatable() {
        #expect(RecoveryAction.retry == .retry)
        #expect(RecoveryAction.custom("open") == .custom("open"))
        #expect(RecoveryAction.retry != .dismiss)
        #expect(RecoveryAction.custom("a") != .custom("b"))
    }
}