import XCTest
@testable import ZephyrLisp

/// Wave-C transient graphics + views + osnap (host-recorded).
final class LispGraphicsTests: XCTestCase {

    func testScreenSwitchesAndClear() async throws {
        var env = LispEnvironment()
        let host = ScriptedLispHost()
        let graph = try await evalString("(graphscr)", env: &env, host: host)
        XCTAssertEqual(graph, .nilValue)
        let text = try await evalString("(textscr)", env: &env, host: host)
        XCTAssertEqual(text, .nilValue)
        let cleared = try await evalString("(grclear)", env: &env, host: host)
        XCTAssertEqual(cleared, .nilValue)
        XCTAssertEqual(host.grClearCount, 1)
        _ = host
    }

    func testGrdrawRecordsVector() async throws {
        var env = LispEnvironment()
        let host = ScriptedLispHost()
        let result = try await evalString(
            "(grdraw '(0 0) '(10 10) 1 1)", env: &env, host: host)
        XCTAssertEqual(result, .nilValue)
        XCTAssertEqual(
            host.grDrawLog,
            [ScriptedLispHost.GrVector(color: 1, from: [0, 0], to: [10, 10])])
        _ = host
    }

    func testGrtextAndRedraw() async throws {
        var env = LispEnvironment()
        let host = ScriptedLispHost()
        _ = try await evalString(
            "(grtext -1 \"status\" 1)", env: &env, host: host)
        XCTAssertEqual(host.grTextLog.count, 1)
        XCTAssertEqual(host.grTextLog[0].box, -1)
        XCTAssertEqual(host.grTextLog[0].text, "status")
        XCTAssertTrue(host.grTextLog[0].highlight)
        _ = try await evalString("(grtext)", env: &env, host: host)
        XCTAssertEqual(host.grTextLog.count, 2)
        _ = try await evalString("(redraw)", env: &env, host: host)
        XCTAssertEqual(host.redrawLog.count, 1)
        XCTAssertNil(host.redrawLog[0].handle)
        XCTAssertEqual(host.redrawLog[0].mode, 1)
        do {
            _ = try await evalString("(redraw nil 9)", env: &env, host: host)
            XCTFail("bad redraw mode should throw")
        } catch is LispError {
            // Expected.
        }
        _ = host
    }

    func testGrvecsParsesColorsAndPairs() async throws {
        var env = LispEnvironment()
        let host = ScriptedLispHost()
        let result = try await evalString(
            "(grvecs '(1 (0 0) (5 5) 3 (1 1) (2 2)))", env: &env, host: host)
        XCTAssertEqual(result, .nilValue)
        XCTAssertEqual(host.grVecsLog.count, 1)
        XCTAssertEqual(
            host.grVecsLog[0],
            [
                ScriptedLispHost.GrVector(color: 1, from: [0, 0], to: [5, 5]),
                ScriptedLispHost.GrVector(color: 3, from: [1, 1], to: [2, 2]),
            ])
        _ = host
    }

    func testSetviewAndOsnap() async throws {
        var env = LispEnvironment()
        let host = ScriptedLispHost()
        let missing = try await evalString(
            "(setview \"Nope\")", env: &env, host: host)
        XCTAssertEqual(missing, .nilValue)
        host.cannedSetView = true
        let restored = try await evalString(
            "(setview \"Plan\")", env: &env, host: host)
        XCTAssertEqual(restored, .t)
        let noSnap = try await evalString(
            "(osnap '(5 5 0) \"_endpoint\")", env: &env, host: host)
        XCTAssertEqual(noSnap, .nilValue)
        host.cannedOsnap = [5, 0, 0]
        let snapped = try await evalString(
            "(osnap '(5 5 0) \"_end\")", env: &env, host: host)
        XCTAssertEqual(
            snapped.properList, [.real(5), .real(0), .real(0)])
        host.cannedOsnap = nil
        let passthrough = try await evalString(
            "(osnap '(5 5) \"_non\")", env: &env, host: host)
        XCTAssertEqual(
            passthrough.properList, [.real(5), .real(5), .real(0)])
        let unsupported = try await evalString(
            "(osnap '(5 5 0) \"_tan\")", env: &env, host: host)
        XCTAssertEqual(unsupported, .nilValue)
        _ = host
    }
}
