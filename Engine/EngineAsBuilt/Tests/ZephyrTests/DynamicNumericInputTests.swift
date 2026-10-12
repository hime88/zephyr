import XCTest
import CSDL3
@testable import ZephyrCore

/// DynamicNumericInput Enter/Escape contract: Enter with all buffers
/// empty must be `.ignored` so the owning command runs its own Enter
/// handling (Line/Polyline finalize); partial input must never be
/// discarded by Enter.
final class DynamicNumericInputTests: XCTestCase {

    func testEmptyEnterIsIgnored() {
        var input = DynamicNumericInput()
        guard case .ignored = input.handleKey(SDL_SCANCODE_RETURN) else {
            XCTFail("empty Enter must be .ignored, got \(input.handleKey(SDL_SCANCODE_RETURN))")
            return
        }
        guard case .ignored = input.handleKey(SDL_SCANCODE_KP_ENTER) else {
            XCTFail("empty numpad Enter must be .ignored")
            return
        }
    }

    func testEmptyEnterInAngleFieldIsIgnored() {
        var input = DynamicNumericInput()
        _ = input.handleKey(SDL_SCANCODE_TAB)
        XCTAssertEqual(input.activeField, .angle)
        guard case .ignored = input.handleKey(SDL_SCANCODE_RETURN) else {
            XCTFail("empty Enter in angle field must be .ignored")
            return
        }
    }

    func testEnterWithValueCommits() {
        var input = DynamicNumericInput()
        _ = input.handleKey(SDL_SCANCODE_1)
        _ = input.handleKey(SDL_SCANCODE_2)
        guard case .commitValue(let dist) = input.handleKey(SDL_SCANCODE_RETURN) else {
            XCTFail("Enter with 12 typed must commit")
            return
        }
        XCTAssertEqual(dist, 12)
    }

    func testEnterWithPartialInputPreservesIt() {
        var input = DynamicNumericInput()
        _ = input.handleKey(SDL_SCANCODE_MINUS)
        guard case .consumed = input.handleKey(SDL_SCANCODE_RETURN) else {
            XCTFail("Enter on invalid partial input must be .consumed")
            return
        }
        XCTAssertEqual(input.distanceBuffer, "-")
    }

    func testEscapeWithEmptyBuffersCancels() {
        var input = DynamicNumericInput()
        guard case .cancel = input.handleKey(SDL_SCANCODE_ESCAPE) else {
            XCTFail("Escape with empty buffers must be .cancel")
            return
        }
    }

    func testEscapeWithInputClearsIt() {
        var input = DynamicNumericInput()
        _ = input.handleKey(SDL_SCANCODE_5)
        guard case .consumed = input.handleKey(SDL_SCANCODE_ESCAPE) else {
            XCTFail("Escape with input must be .consumed")
            return
        }
        XCTAssertFalse(input.hasInput)
    }
}
