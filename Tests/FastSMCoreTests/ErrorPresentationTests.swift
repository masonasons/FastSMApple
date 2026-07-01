//
//  ErrorPresentationTests.swift
//  FastSMCoreTests
//
//  Verifies that thrown errors become specific, copyable messages — the server's
//  own error text surfaces, HTTP status and body land in the copyable detail, and
//  context is folded in.
//

import XCTest
@testable import FastSMCore

final class ErrorPresentationTests: XCTestCase {

    // A Mastodon-style JSON error body should surface the server's human message,
    // not a generic "Server error 422".
    func testMastodonValidationBodySurfacesServerMessage() {
        let err = PlatformError.http(status: 422,
            body: #"{"error":"Validation failed: Text character limit of 500 exceeded"}"#)
        let p = ErrorPresenter.present(err)
        XCTAssertTrue(p.summary.contains("Validation failed: Text character limit of 500 exceeded"),
                      "summary was: \(p.summary)")
        XCTAssertTrue(p.summary.contains("422"))
        // Full status + raw body must be in the copyable detail for a bug report.
        XCTAssertTrue(p.detail.contains("Status: 422"))
        XCTAssertTrue(p.detail.contains("character limit of 500"))
    }

    // Bluesky pairs a machine `error` code with a human `message`; prefer message.
    func testBlueskyBodyPrefersHumanMessage() {
        let err = PlatformError.http(status: 400,
            body: #"{"error":"InvalidRequest","message":"Profile not found"}"#)
        let p = ErrorPresenter.present(err)
        XCTAssertTrue(p.summary.contains("Profile not found"), "summary was: \(p.summary)")
        XCTAssertFalse(p.summary.contains("InvalidRequest"),
                       "should prefer the human message over the machine code")
    }

    // An empty / non-JSON body falls back to a status-based summary but still keeps
    // the raw body in the detail.
    func testEmptyBodyFallsBackToStatus() {
        let p = ErrorPresenter.present(PlatformError.http(status: 500, body: ""))
        XCTAssertTrue(p.summary.contains("500"), "summary was: \(p.summary)")
        XCTAssertTrue(p.detail.contains("Body: (empty)"))
    }

    func testNetworkErrorIsSpecific() {
        let p = ErrorPresenter.present(PlatformError.network("The Internet connection appears to be offline."))
        XCTAssertTrue(p.summary.contains("offline"), "summary was: \(p.summary)")
        XCTAssertTrue(p.detail.contains("Kind: network"))
    }

    func testDecodingKeepsDetailButCleanSummary() {
        let p = ErrorPresenter.present(PlatformError.decoding("keyNotFound(id)"))
        XCTAssertEqual(p.summary, "Couldn't read the server's response.")
        XCTAssertTrue(p.detail.contains("keyNotFound(id)"))
    }

    func testMessagePassesThrough() {
        let p = ErrorPresenter.present(PlatformError.message("Sign-in didn't return an authorization code."))
        XCTAssertEqual(p.summary, "Sign-in didn't return an authorization code.")
    }

    func testNotAuthenticated() {
        let p = ErrorPresenter.present(PlatformError.notAuthenticated)
        XCTAssertEqual(p.summary, "You're not signed in.")
    }

    // Context passed by the caller must appear in the copyable detail.
    func testContextFoldedIntoDetail() {
        let p = ErrorPresenter.present(PlatformError.http(status: 401, body: ""),
                                       context: "Posting a status")
        XCTAssertTrue(p.detail.contains("While: Posting a status"))
    }

    // A non-PlatformError still yields a usable summary from its description.
    func testNonPlatformErrorFallsBackToDescription() {
        struct Custom: LocalizedError { var errorDescription: String? { "Disk is full." } }
        let p = ErrorPresenter.present(Custom())
        XCTAssertEqual(p.summary, "Disk is full.")
    }

    func testServerMessageParserIgnoresNonJSON() {
        XCTAssertNil(ErrorPresenter.serverMessage(from: "Bad Gateway"))
        XCTAssertNil(ErrorPresenter.serverMessage(from: ""))
    }

    func testCancellationDetection() {
        XCTAssertTrue(CancellationError().isCancellation)
        XCTAssertTrue(URLError(.cancelled).isCancellation)
        XCTAssertTrue((URLError(.cancelled) as Error).isCancellation)
        // A real failure is not a cancellation.
        XCTAssertFalse(URLError(.timedOut).isCancellation)
        XCTAssertFalse(PlatformError.network("offline").isCancellation)
        XCTAssertFalse(PlatformError.http(status: 500, body: "").isCancellation)
    }
}
