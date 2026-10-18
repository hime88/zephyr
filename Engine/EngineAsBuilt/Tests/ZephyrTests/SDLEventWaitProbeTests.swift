import XCTest
import CSDL3

/// Probe: does `SDL_WaitEventTimeout(nil, …)` — used as the engine's idle
/// wait — consume the event that wakes it? A pushed MOUSE_BUTTON_DOWN must
/// still be pollable afterwards.
final class SDLEventWaitProbeTests: XCTestCase {

    func testWaitEventTimeoutNilDoesNotConsumeButtonDown() {
        XCTAssertTrue(SDL_InitSubSystem(SDL_INIT_EVENTS))
        defer { SDL_QuitSubSystem(SDL_INIT_EVENTS) }

        var down = SDL_Event()
        down.type = SDL_EVENT_MOUSE_BUTTON_DOWN.rawValue
        down.button.windowID = 3
        down.button.button = 1
        down.button.x = 50
        down.button.y = 60
        XCTAssertTrue(SDL_PushEvent(&down))

        XCTAssertTrue(SDL_WaitEventTimeout(nil, 1))

        var out = SDL_Event()
        XCTAssertTrue(SDL_PollEvent(&out),
                      "MOUSE_BUTTON_DOWN vanished after SDL_WaitEventTimeout(nil, 1)")
        XCTAssertEqual(out.type, SDL_EVENT_MOUSE_BUTTON_DOWN.rawValue)
        XCTAssertEqual(out.button.windowID, 3)
        XCTAssertEqual(out.button.x, 50)
    }
}
