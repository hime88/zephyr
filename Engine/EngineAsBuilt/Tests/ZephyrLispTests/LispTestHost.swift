import XCTest
@testable import ZephyrLisp

/// Scripted host for unit tests: canned answers per request kind, a small
/// system-variable store with AutoCAD-ish defaults, and captured output.
/// A nil canned element means empty input (bare Enter); an exhausted queue
/// is a loud test bug (.hostError), never a silent cancel.
final class ScriptedLispHost: LispHost, @unchecked Sendable {
    var lines: [String?] = []
    var points: [[Double]?] = []
    var pointNumbers: [LispPointInput?] = []
    var entities: [(String, [Double])?] = []
    var deviceEvents: [LispValue] = []
    var cancelNext = false
    var output = ""

    var vars: [String: LispValue] = [
        "OSMODE": .int(0),
        "CMDECHO": .int(1),
        "LUNITS": .int(2),
        "LUPREC": .int(4),
        "AUNITS": .int(0),
        "AUPREC": .int(0),
        "ANGBASE": .real(0),
        "ANGDIR": .int(0),
        "CECOLOR": .string("BYLAYER"),
        "CLAYER": .string("0"),
        "TEXTSTYLE": .string("Standard"),
    ]

    private func next<T>(_ queue: inout [T], what: String) throws -> T {
        if cancelNext {
            cancelNext = false
            throw LispError.userCancel
        }
        guard !queue.isEmpty else {
            throw LispError.hostError("scripted \(what) exhausted")
        }
        return queue.removeFirst()
    }

    func write(_ text: String) async { output += text }

    func requestLine(prompt: String) async throws -> String? {
        _ = prompt
        return try next(&lines, what: "lines")
    }

    func requestPoint(prompt: String, base: [Double]?) async throws -> [Double]? {
        _ = prompt
        _ = base
        return try next(&points, what: "points")
    }

    func requestPointOrNumber(prompt: String, base: [Double]?) async throws -> LispPointInput? {
        _ = prompt
        _ = base
        return try next(&pointNumbers, what: "point-or-numbers")
    }

    func requestEntity(prompt: String) async throws -> (handle: String, point: [Double])? {
        _ = prompt
        guard let answer = try next(&entities, what: "entities") else { return nil }
        return (answer.0, answer.1)
    }

    func readDeviceEvent() async throws -> LispValue {
        if cancelNext {
            cancelNext = false
            throw LispError.userCancel
        }
        guard !deviceEvents.isEmpty else {
            throw LispError.hostError("scripted device events exhausted")
        }
        return deviceEvents.removeFirst()
    }

    func getSystemVar(_ name: String) async -> LispValue? { vars[name] }
    func setSystemVar(_ name: String, _ value: LispValue) async { vars[name] = value }

    var vlaBoxes: [String: (min: [Double], max: [Double])] = [:]

    func vlaBoundingBox(_ handle: String) async throws -> (min: [Double], max: [Double]) {
        guard let box = vlaBoxes[handle] else {
            throw LispError.noActiveDrawing("vla-getboundingbox \(handle)")
        }
        return box
    }

    /// Canned entget assoc lists, keyed by entity handle.
    var entLists: [String: LispValue] = [:]

    func entGet(_ handle: String) async throws -> LispValue {
        guard let list = entLists[handle] else {
            throw LispError.noActiveDrawing("entget \(handle)")
        }
        return list
    }

    // MARK: - Step 4d recording surface

    struct GrVector: Equatable {
        let color: Int
        let from: [Double]
        let to: [Double]
    }

    var grDrawLog: [GrVector] = []
    var grVecsLog: [[GrVector]] = []
    var grVecsTransforms: [[[Double]]?] = []
    var grClearCount = 0
    var grTextLog: [(box: Int, text: String, highlight: Bool)] = []
    var redrawLog: [(handle: String?, mode: Int)] = []
    var cannedSetView = false
    var cannedOsnap: [Double]?
    var layers: [String: Bool] = [:]
    var cannedFile: String?
    var cannedColor: Int?
    var cannedTrueColor: LispValue?

    func grDraw(from: [Double], to: [Double], color: Int, highlight: Bool) async {
        _ = highlight
        grDrawLog.append(GrVector(color: color, from: from, to: to))
    }

    func grVecs(
        _ vectors: [(color: Int, from: [Double], to: [Double])],
        transform: [[Double]]?
    ) async {
        grVecsLog.append(vectors.map { GrVector(color: $0.color, from: $0.from, to: $0.to) })
        grVecsTransforms.append(transform)
    }

    func grClear() async { grClearCount += 1 }

    func grText(box: Int, text: String, highlight: Bool) async {
        grTextLog.append((box: box, text: text, highlight: highlight))
    }

    func redraw(handle: String?, mode: Int) async {
        redrawLog.append((handle: handle, mode: mode))
    }

    func setView(name: String, viewport: Int?) async -> Bool {
        _ = (name, viewport)
        return cannedSetView
    }

    func osnap(point: [Double], modes: [String]) async -> [Double]? {
        _ = (point, modes)
        return cannedOsnap
    }

    func layerNames() async -> [String] { Array(layers.keys) }

    func layerIsOn(_ name: String) async -> Bool? { layers[name] }

    func setLayerIsOn(_ name: String, on: Bool) async -> Bool {
        guard layers[name] != nil else { return false }
        layers[name] = on
        return true
    }

    func requestFile(
        title: String, defaultPath: String, extensions: String, flags: Int
    ) async -> String? {
        _ = (title, defaultPath, extensions, flags)
        return cannedFile
    }

    func requestColor(default defaultACI: Int, allowByLayer: Bool) async -> Int? {
        _ = (defaultACI, allowByLayer)
        return cannedColor
    }

    func requestTrueColor(defaultACI: Int?, allowByLayer: Bool) async -> LispValue? {
        _ = (defaultACI, allowByLayer)
        return cannedTrueColor
    }
}

// MARK: - Shared eval helpers

/// Parses and runs source, returning the last value.
func evalString(
    _ source: String, env: inout LispEnvironment, host: ScriptedLispHost
) async throws -> LispValue {
    let forms = try LispReader().readAll(source)
    return try await LispEvaluator().run(forms, env: &env, host: host)
}

/// Asserts evaluating source yields the expected value (fresh env + host).
func assertEval(
    _ source: String, _ expected: LispValue,
    file: StaticString = #filePath, line: UInt = #line
) async throws {
    var env = LispEnvironment()
    let host = ScriptedLispHost()
    let actual = try await evalString(source, env: &env, host: host)
    XCTAssertEqual(actual, expected, "eval: \(source)", file: file, line: line)
}

/// Asserts evaluating source throws the expected error (fresh env + host).
func assertEvalThrows(
    _ source: String, _ expected: LispError,
    file: StaticString = #filePath, line: UInt = #line
) async {
    var env = LispEnvironment()
    let host = ScriptedLispHost()
    do {
        let value = try await evalString(source, env: &env, host: host)
        XCTFail("expected \(expected), got \(value.prin1String) for: \(source)", file: file, line: line)
    } catch let error as LispError {
        XCTAssertEqual(error, expected, "for: \(source)", file: file, line: line)
    } catch {
        XCTFail("unexpected error \(error) for: \(source)", file: file, line: line)
    }
}
