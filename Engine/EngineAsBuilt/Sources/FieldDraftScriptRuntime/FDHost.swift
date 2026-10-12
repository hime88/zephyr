// MARK: - Host Protocol

public protocol FDHost: Sendable {
    func call(_ name: String, _ args: [FDValue], env: inout FDEnvironment) async throws -> FDValue
}

// MARK: - Capability Protocols

protocol FDCADHost {
    func getpoint(_ prompt: String, base: FDValue?) async throws -> FDValue
    func line(_ a: FDValue, _ b: FDValue) async throws -> FDValue
    func setvar(_ name: String, _ value: FDValue) async throws -> FDValue
}

protocol FDIOHost {
    func readFile(_ path: String) async throws -> String
    func writeFile(_ path: String, _ contents: String) async throws
}

protocol FDNetworkHost {
    func httpGet(_ url: String) async throws -> String
}
