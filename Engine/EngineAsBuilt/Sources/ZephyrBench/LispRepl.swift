import Foundation
import Dispatch
import ZephyrLisp

// =========================================================================
// MARK: - ZephyrBench lisp subcommand
// =========================================================================
//
// Headless AutoLISP driver over a CLI host (stdin/stdout, no drawing):
//   ZephyrBench lisp --eval "(+ 1 2)"     evaluate expressions, print results
//   ZephyrBench lisp file.lsp ...         load files in one shared env
//   ZephyrBench lisp                      stdin REPL (multi-line aware)
//
// Input conventions on stdin: points as "x,y[,z]", entity picks as
// "HANDLE[,x,y]", grread events as "k <text>" / "p x,y", empty line for
// Enter, and CANCEL for Esc. Entity/selection/command builtins report
// clean no-host errors until step 3 binds the CAD host.

enum LispRepl {
    static func run(arguments: [String]) async throws {
        let host = LispCommandLineHost()
        var env = LispEnvironment()
        let evaluator = LispEvaluator()

        var index = 0
        var didAnything = false
        while index < arguments.count {
            if arguments[index] == "--eval", index + 1 < arguments.count {
                let result = try await evalText(
                    arguments[index + 1], evaluator: evaluator, env: &env, host: host)
                LispConsole.line(result.prin1String)
                index += 2
                didAnything = true
            } else {
                let path = arguments[index]
                let result = try await evaluator.load(path: path, env: &env, host: host)
                LispConsole.line("loaded \(result.displayString)")
                index += 1
                didAnything = true
            }
        }
        if !didAnything {
            try await replLoop(evaluator: evaluator, env: &env, host: host)
        }
    }

    private static func replLoop(
        evaluator: LispEvaluator, env: inout LispEnvironment, host: LispCommandLineHost
    ) async throws {
        LispConsole.line("ZephyrLisp 1.0.0 — empty line evaluates, CANCEL cancels input, EOF quits.")
        var buffer = ""
        var prompt = "> "
        while true {
            LispConsole.write(prompt)
            guard let line = readLine(strippingNewline: true) else { return }
            buffer += line + "\n"
            do {
                let forms = try LispReader().readAll(buffer)
                buffer = ""
                prompt = "> "
                if forms.isEmpty { continue }
                let result = try await evaluator.run(forms, env: &env, host: host)
                LispConsole.line(result.prin1String)
            } catch let error as LispError {
                // Incomplete input continues on the next line; real errors reset.
                if case .reader(let message, _, _) = error,
                    message.contains("unexpected end of input") || message.contains("missing )")
                {
                    prompt = ">> "
                    continue
                }
                LispConsole.line("error: \(error)")
                buffer = ""
                prompt = "> "
            }
        }
    }

    private static func evalText(
        _ text: String, evaluator: LispEvaluator,
        env: inout LispEnvironment, host: LispCommandLineHost
    ) async throws -> LispValue {
        let forms = try LispReader().readAll(text)
        return try await evaluator.run(forms, env: &env, host: host)
    }
}

// MARK: - Console

/// Unbuffered stdout writer. C stdio handles (stdout/fflush) are unreachable
/// under Swift 6 strict concurrency, so all REPL/host output funnels through
/// FileHandle writes here (one path keeps piped output ordered).
enum LispConsole {
    static func write(_ text: String) {
        if let data = text.data(using: .utf8) {
            try? FileHandle.standardOutput.write(contentsOf: data)
        }
    }

    static func line(_ text: String = "") {
        write(text + "\n")
    }
}

// MARK: - CLI host

/// Stdin/stdout host: no drawing, dict-backed variables, typed input.
final class LispCommandLineHost: LispHost, @unchecked Sendable {
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
        "FILLMODE": .int(1),
        "GRIDMODE": .int(0),
        "SNAPMODE": .int(0),
        "ORTHOMODE": .int(0),
        "APERTURE": .int(10),
        "DWGNAME": .string("Drawing1.dwg"),
    ]

    func write(_ text: String) async {
        LispConsole.write(text)
    }

    func requestLine(prompt: String) async throws -> String? {
        if !prompt.isEmpty {
            LispConsole.write(prompt)
        }
        guard let line = readLine(strippingNewline: true) else {
            throw LispError.quitRequested
        }
        if line.trimmingCharacters(in: .whitespaces).uppercased() == "CANCEL" {
            throw LispError.userCancel
        }
        return line.isEmpty ? nil : line
    }

    func requestPoint(prompt: String, base: [Double]?) async throws -> [Double]? {
        _ = base
        while true {
            guard let line = try await requestLine(prompt: prompt) else { return nil }
            if let coords = LispInputParsing.parsePointText(line) { return coords }
            await write("Invalid point (want x,y[,z]).\n")
        }
    }

    func requestPointOrNumber(prompt: String, base: [Double]?) async throws -> LispPointInput? {
        _ = base
        // AUNITS for typed-angle parsing, from this host's own store.
        let mode: Int = {
            if case let .int(v) = vars["AUNITS"] { return v }
            return 0
        }()
        while true {
            guard let line = try await requestLine(prompt: prompt) else { return nil }
            if let coords = LispInputParsing.parsePointText(line) { return .point(coords) }
            if let angle = LispInputParsing.parseAngleText(line, mode: mode) { return .number(angle) }
            await write("Invalid point or number.\n")
        }
    }

    func requestEntity(prompt: String) async throws -> (handle: String, point: [Double])? {
        while true {
            guard let line = try await requestLine(prompt: prompt) else { return nil }
            let parts = line.split(separator: ",", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard let handle = parts.first, !handle.isEmpty else {
                await write("Invalid entity pick (want HANDLE[,x,y]).\n")
                continue
            }
            if parts.count == 1 {
                return (handle.uppercased(), [0, 0, 0])
            }
            let pointText = parts.dropFirst().joined(separator: ",")
            guard let coords = LispInputParsing.parsePointText(pointText) else {
                await write("Invalid entity pick (want HANDLE[,x,y]).\n")
                continue
            }
            return (handle.uppercased(), coords)
        }
    }

    func readDeviceEvent() async throws -> LispValue {
        guard let line = try await requestLine(prompt: "") else { return .nilValue }
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("k ") {
            return LispValue(list: [.int(2), .string(String(trimmed.dropFirst(2)))])
        }
        if trimmed.hasPrefix("p ") {
            let coords = LispInputParsing.parsePointText(String(trimmed.dropFirst(2))) ?? []
            return LispValue(list: [.int(3), LispValue(list: coords.map(LispValue.real))])
        }
        return .nilValue
    }

    func getSystemVar(_ name: String) async -> LispValue? { vars[name] }
    func setSystemVar(_ name: String, _ value: LispValue) async { vars[name] = value }
}
