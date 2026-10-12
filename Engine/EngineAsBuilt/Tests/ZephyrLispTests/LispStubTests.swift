import XCTest
@testable import ZephyrLisp

/// Every stub-disposition entry dispatches and throws a clean
/// unsupported-platform error (never unbound-function, never nil).
final class LispStubTests: XCTestCase {

    func testEveryStubThrowsUnsupported() async throws {
        let stubs = LispRegistry.all.filter { $0.disposition == .stub }
        XCTAssertEqual(stubs.count, 17)
        for entry in stubs {
            var env = LispEnvironment()
            let host = ScriptedLispHost()
            XCTAssertTrue(
                LispEvaluator.knows(entry.name.uppercased()), entry.name)
            do {
                _ = try await evalString("(\(entry.name))", env: &env, host: host)
                XCTFail("\(entry.name) should throw unsupportedStub")
            } catch let error as LispError {
                guard case let .unsupportedStub(name) = error else {
                    XCTFail("\(entry.name) threw \(error) instead of unsupportedStub")
                    continue
                }
                XCTAssertEqual(name, entry.name.uppercased())
            }
            _ = host
        }
    }
}
