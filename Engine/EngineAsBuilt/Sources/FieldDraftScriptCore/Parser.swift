import Foundation

// MARK: - FDScript Parser (neutral AST)

public final class FieldDraftScriptParser {
    let tokens: [FieldDraftToken]
    var index = 0
    var macros: [String: [FieldDraftToken]]
    let yieldBody: [FDStmt]?
    let expansionDepth: Int

    // MARK: - Init

    public init(_ source: String, macros: [String: [FieldDraftToken]] = [:], yieldBody: [FDStmt]? = nil, expansionDepth: Int = 0) throws {
        var lexer = FieldDraftLexer(source)
        self.tokens = try lexer.tokenize()
        self.macros = macros
        self.yieldBody = yieldBody
        self.expansionDepth = expansionDepth
    }

    init(tokens: [FieldDraftToken], macros: [String: [FieldDraftToken]], yieldBody: [FDStmt]?, expansionDepth: Int) {
        // internal — used by macro expansion
        self.tokens = tokens
        self.macros = macros
        self.yieldBody = yieldBody
        self.expansionDepth = expansionDepth
    }

    // MARK: - Token state

    public var current: FieldDraftToken { tokens[index] }

    public var isEOF: Bool {
        if case .eof = current { return true }
        return false
    }

    // MARK: - Token navigation

    func advance() {
        if index < tokens.count - 1 { index += 1 }
    }

    func skipNewlines() {
        while case .newline = current { advance() }
    }

    func skipSeparators() {
        while true {
            switch current {
            case .newline, .comment: advance()
            default: return
            }
        }
    }

    // MARK: - Token matching

    func matchIdentifier(_ value: String) -> Bool {
        guard case let .identifier(tokenValue, _, _) = current, tokenValue == value else { return false }
        advance(); return true
    }

    func matchSymbol(_ value: String) -> Bool {
        guard case let .symbol(tokenValue, _, _) = current, tokenValue == value else { return false }
        advance(); return true
    }

    @discardableResult
    func expectIdentifier(_ expected: String? = nil, context: String? = nil) throws -> String {
        guard case let .identifier(value, _, _) = current else {
            if let context { throw parseError("Expected \(context), found \(tokenDescription(current))") }
            throw parseError("Expected identifier, found \(tokenDescription(current))")
        }
        if let expected, value != expected { throw parseError("Expected '\(expected)', found '\(value)'") }
        advance(); return value
    }

    func expectString() throws -> String {
        guard case let .string(value, _, _) = current else {
            throw parseError("Expected string, found \(tokenDescription(current))")
        }
        advance(); return value
    }

    func expectSymbol(_ value: String) throws {
        guard matchSymbol(value) else {
            throw parseError("Expected '\(value)', found \(tokenDescription(current))")
        }
    }

    // MARK: - Error helpers

    func parseError(_ message: String, token: FieldDraftToken? = nil) -> FieldDraftScriptError {
        let t = token ?? current
        return .parse(message, t.line, t.column)
    }

    func tokenDescription(_ token: FieldDraftToken) -> String {
        switch token {
        case let .identifier(value, _, _): return "identifier '\(value)'"
        case let .string(value, _, _): return "string \"\(value)\""
        case let .number(value, _, _): return "number \(value)"
        case let .comment(value, _, _): return "comment ; \(value)"
        case let .symbol(value, _, _): return "symbol '\(value)'"
        case .newline: return "newline"
        case .eof: return "end of file"
        }
    }

    func statementSuggestion(for value: String) -> String? {
        let candidates = Array(FDBuiltinRegistry.allKnown(macros: Set(macros.keys)))
        guard let best = candidates.min(by: { editDistance(value, $0) < editDistance(value, $1) }) else { return nil }
        return editDistance(value, best) <= 3 ? best : nil
    }

    // MARK: - Entry points

    public func parseProgram() throws -> FDProgram {
        var decls: [FDDecl] = []
        skipSeparators()

        while !isEOF {
            if matchIdentifier("macro") {
                try parseMacroDefinition()
            } else if matchIdentifier("function") {
                decls.append(.function(try parseFunctionDefinition()))
            } else if matchIdentifier("alias") {
                decls.append(.alias(try parseAliasDefinition()))
            } else if matchIdentifier("rawTop") {
                decls.append(try parseRawTopDefinition())
            } else {
                decls.append(.command(try parseCommandDefinition()))
            }
            skipSeparators()
        }
        return FDProgram(declarations: decls)
    }

    /// Parse a macro expansion (called when a macro is invoked).
    func parseMacroExpansion(yieldBody: [FDStmt]?) throws -> [FDStmt] {
        var stmts: [FDStmt] = []
        skipSeparators()
        while !isEOF {
            if matchIdentifier("macro") { try parseMacroDefinition() }
            else if matchIdentifier("function") { _ = try parseFunctionDefinition() }
            else { stmts.append(try parseStatement()) }
            skipSeparators()
        }
        return stmts
    }

    // MARK: - Block / macro helpers

    func parseBlock() throws -> [FDStmt] {
        try expectSymbol("{")
        var nodes: [FDStmt] = []
        skipNewlines()
        while !matchSymbol("}") {
            if isEOF { throw parseError("Expected '}' before end of file") }
            if case let .comment(text, _, _) = current {
                advance()
                if !text.isEmpty { nodes.append(.comment(text)) }
                skipNewlines(); continue
            }
            nodes.append(try parseStatement())
            skipNewlines()
        }
        return nodes
    }

    func parseMacroDefinition() throws {
        let name = try expectIdentifier(context: "macro name")
        let bodyTokens = try collectBlockTokens()
        macros[name] = bodyTokens
    }

    func collectBlockTokens() throws -> [FieldDraftToken] {
        try expectSymbol("{")
        var depth = 1
        var collected: [FieldDraftToken] = []
        while depth > 0 {
            if isEOF { throw parseError("Expected '}' before end of file") }
            let token = current; advance()
            if case let .symbol(value, _, _) = token {
                if value == "{" { depth += 1; collected.append(token); continue }
                if value == "}" { depth -= 1; if depth == 0 { break }; collected.append(token); continue }
            }
            collected.append(token)
        }
        let eofLine = current.line; let eofColumn = current.column
        collected.append(.eof(eofLine, eofColumn))
        return collected
    }

    // MARK: - Top-level declarations

    func parseCommandDefinition() throws -> FDCommandDecl {
        _ = try expectIdentifier("command")
        let name = try expectIdentifier()
        let body = try parseBlock()
        return FDCommandDecl(name: name, body: body)
    }

    func parseFunctionDefinition() throws -> FDFunctionDecl {
        let name = try expectIdentifier(context: "function name")
        var params: [String] = []
        try expectSymbol("(")
        if !matchSymbol(")") {
            repeat { params.append(try expectIdentifier(context: "parameter name")) } while matchSymbol(",")
            try expectSymbol(")")
        }
        let body = try parseBlock()
        return FDFunctionDecl(name: name, params: params, body: body)
    }

    func parseAliasDefinition() throws -> FDAliasDecl {
        let aliasName = try expectIdentifier(context: "alias name")
        try expectSymbol("=")
        let targetName = try expectIdentifier(context: "target command name")
        return FDAliasDecl(alias: aliasName, target: targetName)
    }

    func parseRawTopDefinition() throws -> FDDecl {
        if case let .string(value, _, _) = current {
            advance()
            return .rawTop(unescapeRawString(value))
        }
        let expr = try parseExpression()
        return .rawTop(renderExpr(expr))
    }

    // MARK: - Expression rendering helper (for rawTop fallback)

    func renderExpr(_ expr: FDExpr) -> String {
        switch expr {
        case .nil: return "nil"
        case let .bool(v): return v ? "T" : "nil"
        case let .number(v): return String(v)
        case let .string(v): return "\"\(v)\""
        case let .symbol(v): return v
        case let .list(items): return "(" + items.map(renderExpr).joined(separator: " ") + ")"
        case let .call(name, args): return "(\(name) " + args.map(renderExpr).joined(separator: " ") + ")"
        case let .unary(op, v): return "(\(op) \(renderExpr(v)))"
        case let .binary(op, l, r): return "(\(op) \(renderExpr(l)) \(renderExpr(r)))"
        }
    }

    func unescapeRawString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }
}
