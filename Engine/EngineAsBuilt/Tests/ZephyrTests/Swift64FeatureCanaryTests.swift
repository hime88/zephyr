import XCTest
@testable import ZephyrCore

/// Runs the Swift 6.4 feature canary. The compile-time half of the canary is the mere existence of
/// `Swift64FeatureCanary` itself; this test covers the runtime behaviour of the same APIs.
///
/// If this fails after a toolchain update, the experimental features this branch relies on
/// (`LifetimeDependence`, `Lifetimes`) have changed behaviour — see plans/swift-6.4-adoption.md.
final class Swift64FeatureCanaryTests: XCTestCase {

    func testSwift64FeaturesBehaveAsExpected() {
        let failures = Swift64FeatureCanary.run()
        XCTAssertTrue(
            failures.isEmpty,
            "Swift 6.4 feature canary failed for: \(failures.joined(separator: ", "))"
        )
    }
}
