import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(Glibc)
import Glibc
#endif
@testable import ZephyrCore

#if !os(Windows)
/// ODADownloadOperation against a local redirecting server: exercises
/// redirect-following completion and mid-flight cancel on the real
/// URLSession stack (regression net for the Linux _MultiHandle
/// teardown crash: the session must never be invalidated from inside
/// its own delegate callback).
final class ODADownloadOperationTests: XCTestCase {

    private static let port = 18923

    private var server: Process?
    private var savedNoProxy: String?

    override func setUp() async throws {
        try await super.setUp()
        // Keep localhost direct: sandboxes/CI that export all_proxy
        // would otherwise route the fixture through a proxy.
        savedNoProxy = ProcessInfo.processInfo.environment["no_proxy"]
        let bypassed = ((savedNoProxy ?? "").split(separator: ",").map(String.init)
            + ["127.0.0.1", "localhost"]).joined(separator: ",")
        setenv("no_proxy", bypassed, 1)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", "/tmp/oda_server.py", "\(Self.port)"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        server = process
        // Readiness poll: /missing must answer 404.
        let probe = URL(string: "http://127.0.0.1:\(Self.port)/missing")!
        for _ in 0..<100 {
            if let (_, response) = try? await URLSession.shared.data(from: probe),
               (response as? HTTPURLResponse)?.statusCode == 404 {
                return
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTFail("fixture server did not start")
    }

    override func tearDown() async throws {
        server?.terminate()
        server = nil
        if let savedNoProxy {
            setenv("no_proxy", savedNoProxy, 1)
        } else {
            unsetenv("no_proxy")
        }
        try await super.tearDown()
    }

    private func destination(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("oda-op-\(name)-\(Int.random(in: 0...Int.max))")
    }

    func testRedirectChainCompletes() async throws {
        let dest = destination("redirect")
        let operation = ODADownloadOperation(destination: dest) { _ in }
        let url = URL(string: "http://127.0.0.1:\(Self.port)/r1")!
        let result = try await operation.download(from: url)
        XCTAssertEqual(result, dest)
        let attrs = try FileManager.default.attributesOfItem(atPath: dest.path)
        XCTAssertEqual(attrs[.size] as? Int, 2 * 1024 * 1024)
        try? FileManager.default.removeItem(at: dest)
    }

    func testCancelMidFlight() async throws {
        let dest = destination("cancel")
        let operation = ODADownloadOperation(destination: dest) { _ in }
        let url = URL(string: "http://127.0.0.1:\(Self.port)/slow")!
        let task = Task { try await operation.download(from: url) }
        try await Task.sleep(nanoseconds: 700_000_000)
        operation.cancel()
        do {
            _ = try await task.value
            XCTFail("cancelled download should throw")
        } catch is CancellationError {
            // Expected.
        }
    }
}
#endif
