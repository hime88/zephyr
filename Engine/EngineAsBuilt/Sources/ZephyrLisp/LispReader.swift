// LispReader: AutoLISP surface syntax to LispValue forms.
//
// Supports atoms, strings with \" and \\ escapes, integers, reals,
// quote sugar ('x), comments (; to end of line), and dotted pairs
// ((0 . "LINE")). Symbols normalize to uppercase. No backquote,
// no |pipes| (clean errors). Numbers parse strictly: a token is a
// number only when the whole token scans as one.

/// Reads one or more top-level AutoLISP forms from text.
public struct LispReader: Sendable {
    public init() {}

    /// Reads every form in `text`. Throws with line/column on malformed input.
    public func readAll(_ text: String, sourceName: String = "<input>") throws -> [LispValue] {
        _ = sourceName
        var cursor = Cursor(text)
        var forms: [LispValue] = []
        cursor.skipTrivia()
        while !cursor.isEOF {
            forms.append(try readForm(&cursor))
            cursor.skipTrivia()
        }
        return forms
    }

    /// Reads exactly one form (used by the read builtin and the REPL).
    public func readOne(_ text: String) throws -> LispValue {
        var cursor = Cursor(text)
        cursor.skipTrivia()
        if cursor.isEOF { return .nilValue }
        return try readForm(&cursor)
    }

    // MARK: - Forms

    private func readForm(_ cursor: inout Cursor) throws -> LispValue {
        guard let ch = cursor.peek else {
            throw LispError.reader(message: "unexpected end of input", line: cursor.line, column: cursor.column)
        }
        switch ch {
        case "(":
            cursor.advance()
            return try readList(&cursor)
        case ")":
            throw LispError.reader(message: "unexpected )", line: cursor.line, column: cursor.column)
        case "'":
            cursor.advance()
            cursor.skipTrivia()
            let quoted = try readForm(&cursor)
            return .init(list: [.symbol("QUOTE"), quoted])
        case "\"":
            return try .string(readString(&cursor))
        default:
            return readAtom(&cursor)
        }
    }

    private func readList(_ cursor: inout Cursor) throws -> LispValue {
        var items: [LispValue] = []
        var dottedTail: LispValue?
        cursor.skipTrivia()
        while true {
            guard let ch = cursor.peek else {
                throw LispError.reader(message: "unexpected end of input (missing ))", line: cursor.line, column: cursor.column)
            }
            if ch == ")" {
                cursor.advance()
                break
            }
            if ch == ".", cursor.peekNextIsDelimiter {
                cursor.advance()
                cursor.skipTrivia()
                dottedTail = try readForm(&cursor)
                cursor.skipTrivia()
                guard cursor.peek == ")" else {
                    throw LispError.reader(
                        message: "expected ) after dotted tail", line: cursor.line, column: cursor.column)
                }
                cursor.advance()
                break
            }
            items.append(try readForm(&cursor))
            cursor.skipTrivia()
        }
        if let tail = dottedTail {
            guard !items.isEmpty else {
                throw LispError.reader(message: "dotted pair needs a head element", line: cursor.line, column: cursor.column)
            }
            // (a b . c) == (cons a (cons b c)).
            var out = tail
            for item in items.reversed() { out = .cons(head: item, tail: out) }
            return out
        }
        return LispValue(list: items)
    }

    private func readString(_ cursor: inout Cursor) throws -> String {
        // Opening quote.
        let startLine = cursor.line
        let startColumn = cursor.column
        cursor.advance()
        var out = ""
        while let ch = cursor.peek {
            if ch == "\"" {
                cursor.advance()
                return out
            }
            if ch == "\\" {
                cursor.advance()
                guard let escaped = cursor.peek else { break }
                switch escaped {
                case "n": out.append("\n")
                case "t": out.append("\t")
                case "r": out.append("\r")
                case "\"": out.append("\"")
                case "\\": out.append("\\")
                default: out.append(escaped)
                }
                cursor.advance()
            } else if ch == "\n" {
                // AutoLISP strings may span lines; keep the newline.
                out.append(ch)
                cursor.advance()
            } else {
                out.append(ch)
                cursor.advance()
            }
        }
        throw LispError.reader(message: "unterminated string", line: startLine, column: startColumn)
    }

    private func readAtom(_ cursor: inout Cursor) -> LispValue {
        var token = ""
        while let ch = cursor.peek, !ch.isLispDelimiter {
            token.append(ch)
            cursor.advance()
        }
        if let number = parseNumber(token) { return number }
        // nil reads as nil (any case); T stays a self-evaluating symbol.
        if token.uppercased() == "NIL" { return .nilValue }
        return .symbol(token.uppercased())
    }

    /// Strict whole-token number scan: [+/-]digits[.digits][e[+/-]digits].
    /// A token with a dot or exponent is real; otherwise int (32-bit wrapped).
    func parseNumber(_ token: String) -> LispValue? {
        guard !token.isEmpty else { return nil }
        let chars = Array(token)
        var index = 0
        if chars[index] == "+" || chars[index] == "-" {
            index += 1
            guard index < chars.count else { return nil }
        }
        var sawDigit = false
        var sawDot = false
        var sawExp = false
        while index < chars.count {
            let ch = chars[index]
            if ch.isWholeNumber {
                sawDigit = true
                index += 1
            } else if ch == ".", !sawDot, !sawExp {
                sawDot = true
                index += 1
            } else if (ch == "e" || ch == "E"), !sawExp, sawDigit {
                sawExp = true
                index += 1
                if index < chars.count, chars[index] == "+" || chars[index] == "-" { index += 1 }
                var expDigits = false
                while index < chars.count, chars[index].isWholeNumber {
                    expDigits = true
                    index += 1
                }
                guard expDigits else { return nil }
            } else {
                return nil
            }
        }
        guard sawDigit else { return nil }
        if sawDot || sawExp {
            guard let value = Double(token) else { return nil }
            return .real(value)
        }
        guard let value = Int(token) else { return nil }
        return .int(LispValue.wrap32(value))
    }
}

// MARK: - Cursor

private struct Cursor: Sendable {
    let text: String
    var index: String.Index
    var line: Int
    var column: Int

    init(_ text: String) {
        self.text = text
        self.index = text.startIndex
        self.line = 1
        self.column = 1
    }

    var isEOF: Bool { index >= text.endIndex }
    var peek: Character? { isEOF ? nil : text[index] }

    /// True when the character after the current one ends a token.
    var peekNextIsDelimiter: Bool {
        let next = text.index(after: index)
        guard next < text.endIndex else { return true }
        return text[next].isLispDelimiter
    }

    mutating func advance() {
        guard !isEOF else { return }
        if text[index].isNewline {
            line += 1
            column = 1
        } else {
            column += 1
        }
        index = text.index(after: index)
    }

    mutating func skipTrivia() {
        while !isEOF {
            let ch = text[index]
            if ch.isWhitespace {
                advance()
            } else if ch == ";" {
                while !isEOF, !text[index].isNewline { advance() }
            } else {
                return
            }
        }
    }
}


private extension Character {
    var isLispDelimiter: Bool {
        isWhitespace || self == "(" || self == ")" || self == "\"" || self == "'" || self == ";"
    }
}
