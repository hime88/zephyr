// MARK: - Lexer

public struct FieldDraftLexer {
    private let chars: [Character]
    private var index = 0
    private var line = 1
    private var column = 1

    public init(_ source: String) {
        self.chars = Array(source)
    }

    public mutating func tokenize() throws -> [FieldDraftToken] {
        var tokens: [FieldDraftToken] = []

        while let ch = peek() {
            if ch == " " || ch == "\t" || ch == "\r" { advance(); continue }
            if ch == "\n" {
                let tokenLine = line; let tokenColumn = column
                advance(); tokens.append(.newline(tokenLine, tokenColumn)); continue
            }
            if ch == ";" { tokens.append(readComment()); continue }
            if ch == "/", peek(offset: 1) == "/" { tokens.append(readSlashComment()); continue }
            if ch == "\"" { tokens.append(try readString()); continue }
            if ch.isNumber || (ch == "." && peek(offset: 1)?.isNumber == true) {
                tokens.append(readNumber()); continue
            }
            if isIdentifierStart(ch) { tokens.append(readIdentifier()); continue }
            if let two = twoCharacterSymbol() {
                let tokenLine = line; let tokenColumn = column
                advance(); advance(); tokens.append(.symbol(two, tokenLine, tokenColumn)); continue
            }
            if "{}(),=+-*/<>[]".contains(ch) {
                let tokenLine = line; let tokenColumn = column
                advance(); tokens.append(.symbol(String(ch), tokenLine, tokenColumn)); continue
            }
            throw FieldDraftScriptError.lex("Unexpected character '\(ch)'", line, column)
        }
        tokens.append(.eof(line, column))
        return tokens
    }

    private func peek(offset: Int = 0) -> Character? {
        let i = index + offset
        guard i >= 0 && i < chars.count else { return nil }
        return chars[i]
    }

    @discardableResult
    private mutating func advance() -> Character? {
        guard index < chars.count else { return nil }
        let ch = chars[index]; index += 1
        if ch == "\n" { line += 1; column = 1 } else { column += 1 }
        return ch
    }

    private func isIdentifierStart(_ ch: Character) -> Bool { ch.isLetter || ch == "_" }
    private func isIdentifierPart(_ ch: Character) -> Bool {
        ch.isLetter || ch.isNumber || ch == "_" || ch == "*" || ch == "?" || ch == "-"
    }

    private func twoCharacterSymbol() -> String? {
        guard let a = peek(), let b = peek(offset: 1) else { return nil }
        let value = String([a, b])
        return [">=", "<=", "==", "!="].contains(value) ? value : nil
    }

    private mutating func readIdentifier() -> FieldDraftToken {
        let tokenLine = line; let tokenColumn = column
        var value = ""
        while let ch = peek(), isIdentifierPart(ch) { value.append(ch); advance() }
        return .identifier(value, tokenLine, tokenColumn)
    }

    private mutating func readNumber() -> FieldDraftToken {
        let tokenLine = line; let tokenColumn = column
        var value = ""; var hasDot = false
        while let ch = peek() {
            if ch == "." { guard !hasDot else { break }; hasDot = true; value.append(ch); advance(); continue }
            guard ch.isNumber else { break }; value.append(ch); advance()
        }
        if let ch = peek(), ch == "e" || ch == "E" {
            let next = peek(offset: 1)
            let afterSign = peek(offset: 2)
            let hasExponentDigits = next?.isNumber == true || ((next == "+" || next == "-") && afterSign?.isNumber == true)
            if hasExponentDigits {
                value.append(ch); advance()
                if let sign = peek(), sign == "+" || sign == "-" { value.append(sign); advance() }
                while let digit = peek(), digit.isNumber { value.append(digit); advance() }
            }
        }
        return .number(value, tokenLine, tokenColumn)
    }

    private mutating func readString() throws -> FieldDraftToken {
        let tokenLine = line; let tokenColumn = column
        var value = ""; advance()
        while let ch = peek() {
            if ch == "\"" { advance(); return .string(value, tokenLine, tokenColumn) }
            if ch == "\\" {
                advance()
                guard let escaped = peek() else { throw FieldDraftScriptError.lex("Unterminated escape sequence", line, column) }
                switch escaped {
                case "n": value += "\\n"; case "t": value += "\\t"; case "r": value += "\\r"
                case "\"": value += "\\\""; case "\\": value += "\\\\"
                default: value += "\\\(escaped)"
                }
                advance(); continue
            }
            value.append(ch); advance()
        }
        throw FieldDraftScriptError.lex("Unterminated string", tokenLine, tokenColumn)
    }

    private mutating func readComment() -> FieldDraftToken {
        let tokenLine = line; let tokenColumn = column; advance()
        var value = ""
        while let ch = peek(), ch != "\n" { value.append(ch); advance() }
        return .comment(value.trimmingCharacters(in: .whitespaces), tokenLine, tokenColumn)
    }

    private mutating func readSlashComment() -> FieldDraftToken {
        let tokenLine = line; let tokenColumn = column; advance(); advance()
        var value = ""
        while let ch = peek(), ch != "\n" { value.append(ch); advance() }
        return .comment(value.trimmingCharacters(in: .whitespaces), tokenLine, tokenColumn)
    }
}
