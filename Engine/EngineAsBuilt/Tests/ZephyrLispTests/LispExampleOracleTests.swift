import XCTest
@testable import ZephyrLisp

/// Step-4e registry example oracle: every one of the 305 inventory
/// entries carries an `example:` string, and this test runs each one
/// through the real evaluator on a scripted host.
///
/// Classification per entry:
/// - value returned: non-stub entries pass (plus a `;; Returns:`
///   scalar/list assertion when the annotation is machine-readable,
///   with epsilon-tolerant real comparison); stub entries fail (the
///   stub must throw, not succeed).
/// - unboundFunction, arity, typeMismatch, reader errors: FAIL —
///   the example and the implementation disagree about the contract.
/// - unsupportedStub on a stub entry: pass. Anywhere else: FAIL.
/// - hostError / noActiveDrawing / userCancel / quitRequested /
///   exitWithValue / nested errors: SKIP — the example needs CAD
///   state, a command host, or interactive input the scripted host
///   cannot provide. Skips are counted and reported, never silent.
/// - allowlisted entries (wrong oracle text or un-runnable example,
///   each with a recorded reason): the hard failure is expected and
///   counted, never silent; if an allowlisted entry ever passes or
///   soft-skips, the harness fails as stale so the allowlist cannot
///   rot.
///
/// The harness runs with the working directory pointed at a fresh
/// temp dir so file examples cannot touch the checkout, and purges
/// the Lisp UserDefaults namespaces afterwards.
final class LispExampleOracleTests: XCTestCase {

    /// Entries whose oracle text is wrong or whose example cannot run
    /// headless, with the verified reason. The implementation is
    /// correct in every case (triaged in step 4e); the vendored
    /// oracle HTML is left pristine for upstream sync.
    private static let allowlist: [String: String] = [
        // Annotation drops the duplicate: (vl-sort '(3 1 2 3) '<)
        // is (1 2 3 3); impl verified.
        "vl-sort": "annotation drops duplicate element",
        // Annotation uses `1.`-style dotted notation, which the reader
        // (correctly, like AutoCAD) parses as real 1.0; the value
        // (cons 1 2) -> (1 . 2) is verified by unit test.
        "cons": "dotted-pair annotation unparseable",
        // Same `2.` notation as cons; (vl-list* 1 2 3) -> (1 2 . 3).
        "vl-list*": "dotted-pair annotation unparseable",
        // (cdr '(10. 20)): `10.` is real 10.0, so cdr is (20);
        // annotation claims 20.
        "cdr": "annotation misreads `10.` real literal",
        // (vl-string-translate "abc" "123" "cabin") is "312in"
        // (a->1, b->2, c->3); annotation "31bin" drops the 2.
        "vl-string-translate": "annotation typo drops a mapping",
        // Examples reference unbound dict/ss/tracee variables
        // (documentation shorthand for drawing state); the type
        // errors are correct AutoCAD behavior for nil arguments.
        "dictadd": "example uses unbound dict var",
        "dictnext": "example uses unbound dict var",
        "dictremove": "example uses unbound dict var",
        "dictrename": "example uses unbound dict var",
        "dictsearch": "example uses unbound dict var",
        "sslength": "example uses unbound selection set",
        "ssname": "example uses unbound selection set",
        "ssnamex": "example uses unbound selection set",
        "trace": "example traces an undefined function",
        "untrace": "example untraces an undefined function",
        "vl-catch-all-error-p": "example uses unbound error object",
        // Zephyr reports its own engine string by design.
        "ver": "vendor string differs by design",
        // Windows-only path; nil on this platform is correct.
        "vl-file-directory-p": "example path is Windows-only",
    ]

    override func tearDown() {
        for key in UserDefaults.standard.dictionaryRepresentation().keys
            where key.hasPrefix("ZephyrLispRegistry.")
                || key.hasPrefix("ZephyrLispCfg.") {
            UserDefaults.standard.removeObject(forKey: key)
        }
        super.tearDown()
    }

    func testAllRegistryExamples() async throws {
        XCTAssertEqual(LispRegistry.all.count, 305)
        let previousCWD = FileManager.default.currentDirectoryPath
        let sandbox = FileManager.default.temporaryDirectory
            .appendingPathComponent("lisp-oracle-\(Int.random(in: 0...Int.max))")
        try FileManager.default.createDirectory(
            at: sandbox, withIntermediateDirectories: true)
        _ = FileManager.default.changeCurrentDirectoryPath(sandbox.path)
        defer { _ = FileManager.default.changeCurrentDirectoryPath(previousCWD) }

        var failures: [String] = []
        var skips: [String: Int] = [:]
        var returnsAsserted = 0

        for entry in LispRegistry.all.sorted(by: { $0.name < $1.name }) {
            var env = LispEnvironment()
            let host = ScriptedLispHost()
            host.lines = Array(repeating: nil, count: 32)
            host.points = Array(repeating: nil, count: 32)
            host.pointNumbers = Array(repeating: nil, count: 32)
            host.entities = Array(repeating: nil, count: 32)
            let allowedReason = Self.allowlist[entry.name]
            switch await runOracleEntry(entry, env: &env, host: host) {
            case let .pass(asserted):
                if asserted { returnsAsserted += 1 }
                if let reason = allowedReason {
                    failures.append(
                        "\(entry.name): stale allowlist (now passes): \(reason)")
                }
            case let .softSkip(kind):
                if let reason = allowedReason {
                    failures.append(
                        "\(entry.name): stale allowlist (now skips): \(reason)")
                } else {
                    skips[kind, default: 0] += 1
                }
            case let .hardFail(message):
                if allowedReason != nil {
                    skips["allowlisted", default: 0] += 1
                } else {
                    failures.append(message)
                }
            }
            _ = host
        }

        print(
            "oracle: \(LispRegistry.all.count) examples, "
                + "\(failures.count) failures, "
                + "\(skips.values.reduce(0, +)) skips \(skips), "
                + "\(returnsAsserted) Returns: assertions")
        XCTAssertTrue(
            failures.isEmpty,
            "Example oracle failures:\n" + failures.sorted().joined(separator: "\n"))
    }

    private enum OracleOutcome {
        case pass(asserted: Bool)
        case softSkip(kind: String)
        case hardFail(message: String)
    }

    private func runOracleEntry(
        _ entry: LispBuiltinDescriptor,
        env: inout LispEnvironment,
        host: ScriptedLispHost
    ) async -> OracleOutcome {
        let forms: [LispValue]
        do {
            forms = try LispReader().readAll(entry.example)
        } catch {
            return .hardFail(message: "\(entry.name): example does not parse: \(error)")
        }
        do {
            let result = try await LispEvaluator().run(
                forms, env: &env, host: host)
            if entry.disposition == .stub {
                return .hardFail(message: "\(entry.name): stub example returned \(result)")
            }
            if Self.hasReturnsAnnotation(entry.example),
               let expected = Self.expectedReturn(from: entry.example) {
                guard Self.valuesMatch(expected, result) else {
                    return .hardFail(
                        message: "\(entry.name): ;; Returns: mismatch: "
                            + "expected \(expected), got \(result)")
                }
                return .pass(asserted: true)
            }
            return .pass(asserted: false)
        } catch let error as LispError {
            switch error {
            case let .unsupportedStub(name):
                if entry.disposition == .stub {
                    XCTAssertEqual(name, entry.name.uppercased())
                    return .pass(asserted: false)
                }
                return .hardFail(message: "\(entry.name): unexpected unsupportedStub")
            case .hostError, .noActiveDrawing:
                return .softSkip(kind: "needs-host")
            case .userCancel, .quitRequested, .exitWithValue:
                return .softSkip(kind: "terminating")
            case .nestedInteractive, .nestedCommand:
                return .softSkip(kind: "nested-command")
            case .unboundFunction, .arity, .typeMismatch,
                 .reader, .divisionByZero, .protectedSymbol,
                 .stackOverflow, .errorHandlerFailed:
                return .hardFail(message: "\(entry.name): hard error: \(error)")
            }
        } catch {
            return .hardFail(message: "\(entry.name): non-Lisp error: \(error)")
        }
    }

    /// Epsilon-tolerant equality for Returns: comparison: reals match
    /// within 1e-6 absolute + relative (annotations round), compared
    /// recursively through lists; int/real mixing still fails so type
    /// bugs stay visible.
    private static func valuesMatch(_ expected: LispValue, _ actual: LispValue) -> Bool {
        switch (expected, actual) {
        case let (.real(x), .real(y)):
            return abs(x - y) <= 1e-6 + 1e-6 * max(abs(x), abs(y))
        case let (.cons(xHead, xTail), .cons(yHead, yTail)):
            return valuesMatch(xHead, yHead) && valuesMatch(xTail, yTail)
        default:
            return expected == actual
        }
    }

    private static func hasReturnsAnnotation(_ example: String) -> Bool {
        example.contains(";; Returns:")
    }

    /// Parses the last `;; Returns: <value>` annotation into a Lisp
    /// value when the annotation is machine-readable (scalar or
    /// parenthesized list); nil means "not assertable, skip".
    private static func expectedReturn(from example: String) -> LispValue? {
        let marker = ";; Returns:"
        guard let range = example.range(of: marker, options: .backwards) else {
            return nil
        }
        let tail = example[range.upperBound...]
        let line = tail.prefix(while: { $0 != "\n" })
            .trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty else { return nil }
        // Scalars and quoted strings must match exactly; anything with
        // trailing prose ("T or nil") is not assertable.
        if line == "T" { return .t }
        if line == "nil" || line == "NIL" { return .nilValue }
        if let number = Int(line) { return .int(number) }
        if let number = Double(line) { return .real(number) }
        if line.hasPrefix("\""), line.hasSuffix("\""), line.count >= 2 {
            // Annotations use Lisp-string-literal escaping.
            let inner = String(line.dropFirst().dropLast())
                .replacingOccurrences(of: "\\\"", with: "\"")
                .replacingOccurrences(of: "\\\\", with: "\\")
            return .string(inner)
        }
        // Parenthesized lists (including dotted pairs) via the reader.
        if line.hasPrefix("(") {
            return try? LispReader().readOne(String(line))
        }
        return nil
    }
}
