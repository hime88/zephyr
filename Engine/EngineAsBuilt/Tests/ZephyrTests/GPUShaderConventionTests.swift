import XCTest
import SwiftSDL
@testable import ZephyrCore

final class GPUShaderConventionTests: XCTestCase {
    func testPlatformShaderConvention() {
        let convention = EngineRenderer.gpuShaderConvention()
        #if os(macOS) || os(iOS)
        XCTAssertEqual(convention.fileExt, ".msl")
        XCTAssertEqual(convention.format, UInt32(SDL_GPU_SHADERFORMAT_MSL))
        XCTAssertEqual(convention.entrypoint, "main0")
        #elseif os(Linux)
        XCTAssertEqual(convention.fileExt, ".spv")
        XCTAssertEqual(convention.format, UInt32(SDL_GPU_SHADERFORMAT_SPIRV))
        XCTAssertEqual(convention.entrypoint, "main")
        #else
        XCTAssertEqual(convention.fileExt, ".dxil")
        XCTAssertEqual(convention.format, UInt32(SDL_GPU_SHADERFORMAT_DXIL))
        XCTAssertEqual(convention.entrypoint, "main")
        #endif
    }
}
