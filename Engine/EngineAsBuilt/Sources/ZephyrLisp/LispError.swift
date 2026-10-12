// LispError: every failure mode of the reader, evaluator, and hosts.
//
// Messages are the strings delivered to *error* and vl-catch-all objects,
// so they stay close to AutoCAD's wording ("bad argument type", "too few
// arguments", "quit / exit abort").

/// Every failure the Lisp engine can report.
public enum LispError: Error, Sendable, Equatable, CustomStringConvertible {
    /// Reader failure with 1-based line/column in the source.
    case reader(message: String, line: Int, column: Int)
    /// Call of an undefined function.
    case unboundFunction(String)
    /// Wrong argument count.
    case arity(name: String, expected: String, got: Int)
    /// Wrong argument type.
    case typeMismatch(name: String, expected: String, got: LispValue)
    /// Division (or rem) by zero.
    case divisionByZero
    /// User pressed Esc / cancelled input. Delivered to *error* as
    /// "quit / exit abort", then rethrown so the driver can finish quietly.
    case userCancel
    /// (exit)/(quit): unwinds everything; never caught by *error*.
    case quitRequested
    /// Redefinition of a protected symbol (T, nil).
    case protectedSymbol(String)
    /// Lisp nesting deeper than the evaluation limit.
    case stackOverflow
    /// (command) tried to start an interactive command from Lisp.
    case nestedInteractive(String)
    /// (command) re-entered while another (command) is running.
    case nestedCommand
    /// Call of a stubbed builtin (vl-vbarun, arxload, ...).
    case unsupportedStub(String)
    /// Host has no active drawing for entity/selection work.
    case noActiveDrawing(String)
    /// Host-side failure (dialog, process, undo, ...).
    case hostError(String)
    /// Errors raised inside a *error* handler.
    case errorHandlerFailed(String)
    /// vl-exit-with-value: abort evaluation, run() returns the value.
    case exitWithValue(LispValue)

    public var description: String {
        switch self {
        case let .reader(message, line, column):
            return "read error at \(line):\(column): \(message)"
        case let .unboundFunction(name):
            return "no function definition: \(name)"
        case let .arity(name, expected, got):
            return "bad argument count for \(name): expected \(expected), got \(got)"
        case let .typeMismatch(name, expected, got):
            return "bad argument type for \(name): expected \(expected), got \(got.prin1String)"
        case .divisionByZero:
            return "divide by zero"
        case .userCancel:
            return "quit / exit abort"
        case .quitRequested:
            return "quit / exit abort"
        case let .protectedSymbol(name):
            return "cannot bind protected symbol: \(name)"
        case .stackOverflow:
            return "stack overflow: nesting deeper than the evaluation limit"
        case let .nestedInteractive(name):
            return "cannot start interactive command \(name) from (command ...)"
        case .nestedCommand:
            return "(command ...) re-entered while a command is running"
        case let .unsupportedStub(name):
            return "\(name) is not supported on this platform"
        case let .noActiveDrawing(what):
            return "no active drawing for \(what)"
        case let .hostError(message):
            return message
        case let .errorHandlerFailed(message):
            return "error inside *error* handler: \(message)"
        case let .exitWithValue(value):
            return "exit with value: \(value.prin1String)"
        }
    }

    /// True for errors vl-catch-all-apply must NOT swallow.
    var isFatalToCatchAll: Bool {
        if case .quitRequested = self { return true }
        if case .exitWithValue = self { return true }
        return false
    }
}
