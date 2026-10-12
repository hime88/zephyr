// MARK: - Error Types

public enum FieldDraftScriptError: Error, CustomStringConvertible {
    case lex(String, Int, Int)
    case parse(String, Int, Int)

    public var description: String {
        switch self {
        case let .lex(message, line, column):
            return "Lex error at \(line):\(column): \(message)"
        case let .parse(message, line, column):
            return "Parse error at \(line):\(column): \(message)"
        }
    }
}
