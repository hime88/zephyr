// MARK: - Runtime Errors

public enum FDRuntimeError: Error, CustomStringConvertible {
    case unknownCommand(String)
    case unknownFunction(String)
    case typeMismatch(String)
    case divisionByZero

    public var description: String {
        switch self {
        case let .unknownCommand(name): return "Unknown command: \(name)"
        case let .unknownFunction(name): return "Unknown function: \(name)"
        case let .typeMismatch(msg): return "Type mismatch: \(msg)"
        case .divisionByZero: return "Division by zero"
        }
    }
}
