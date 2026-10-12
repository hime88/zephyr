import XCTest
@testable import ZephyrCore

/// AppImage launch policy: FUSE-less hosts must start extracted, and a
/// directly-launched AppImage that fails with mount errors gets one
/// extract-and-run retry. Pure-helper pins (no processes spawned).
final class ODADWGConverterTests: XCTestCase {

    func testAppImageDetection() {
        XCTAssertTrue(ODADWGConverter.isAppImageBundle(
            path: "/x/ODAFileConverter.AppImage"))
        XCTAssertTrue(ODADWGConverter.isAppImageBundle(
            path: "/x/oda.appimage"))
        XCTAssertFalse(ODADWGConverter.isAppImageBundle(
            path: "/Applications/ODAFileConverter.app/Contents/MacOS/ODAFileConverter"))
        XCTAssertFalse(ODADWGConverter.isAppImageBundle(
            path: "C:\\ODA\\ODAFileConverter.exe"))
    }

    func testExtractAndRunDecision() {
        XCTAssertTrue(ODADWGConverter.appImageNeedsExtractAndRun(
            path: "/x/ODAFileConverter.AppImage", fuseDevicePresent: false))
        XCTAssertFalse(ODADWGConverter.appImageNeedsExtractAndRun(
            path: "/x/ODAFileConverter.AppImage", fuseDevicePresent: true))
        XCTAssertFalse(ODADWGConverter.appImageNeedsExtractAndRun(
            path: "/usr/bin/ODAFileConverter", fuseDevicePresent: false))
    }

    func testFuseFailureSmell() {
        XCTAssertTrue(ODADWGConverter.looksLikeFuseFailure(
            "Cannot mount AppImage, please check your FUSE setup"))
        XCTAssertTrue(ODADWGConverter.looksLikeFuseFailure(
            "dlopen(): error loading libfuse.so.2"))
        XCTAssertFalse(ODADWGConverter.looksLikeFuseFailure(
            "Error: input directory not found"))
        XCTAssertFalse(ODADWGConverter.looksLikeFuseFailure(""))
    }
}
