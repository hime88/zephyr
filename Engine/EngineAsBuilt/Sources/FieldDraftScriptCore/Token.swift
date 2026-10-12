// MARK: - Token Types

public enum FieldDraftToken: Equatable, Sendable {
    case identifier(String, Int, Int)
    case string(String, Int, Int)
    case number(String, Int, Int)
    case comment(String, Int, Int)
    case symbol(String, Int, Int)
    case newline(Int, Int)
    case eof(Int, Int)

    var line: Int {
        switch self {
        case let .identifier(_, line, _), let .string(_, line, _),
             let .number(_, line, _), let .comment(_, line, _),
             let .symbol(_, line, _), let .newline(line, _), let .eof(line, _):
            return line
        }
    }

    var column: Int {
        switch self {
        case let .identifier(_, _, column), let .string(_, _, column),
             let .number(_, _, column), let .comment(_, _, column),
             let .symbol(_, _, column), let .newline(_, column), let .eof(_, column):
            return column
        }
    }
}
