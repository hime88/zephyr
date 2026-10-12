// MARK: - Expression Parsing

extension FieldDraftScriptParser {

    func parseExpression() throws -> FDExpr { try parseComparison() }

    func parseComparison() throws -> FDExpr {
        var left = try parseAdditive()
        while case let .symbol(op, _, _) = current, [">", "<", ">=", "<=", "==", "!="].contains(op) {
            advance()
            let right = try parseAdditive()
            left = .binary(op, left, right)
        }
        return left
    }

    func parseAdditive() throws -> FDExpr {
        var left = try parseMultiplicative()
        while case let .symbol(op, _, _) = current, op == "+" || op == "-" {
            advance()
            let right = try parseMultiplicative()
            left = .binary(op, left, right)
        }
        return left
    }

    func parseMultiplicative() throws -> FDExpr {
        var left = try parseUnary()
        while case let .symbol(op, _, _) = current, op == "*" || op == "/" {
            advance()
            let right = try parseUnary()
            left = .binary(op, left, right)
        }
        return left
    }

    func parseUnary() throws -> FDExpr {
        if matchSymbol("-") {
            return .unary("-", try parseUnary())
        }
        return try parsePrimary()
    }

    func parsePrimary() throws -> FDExpr {
        switch current {
        case let .number(value, _, _):
            advance()
            return .number(Double(value) ?? 0)
        case let .string(value, _, _):
            advance()
            return .string(value)
        case let .identifier(name, _, _):
            advance()
            if matchSymbol("(") {
                return try parseFunctionCall(name)
            }
            if name == "nil" { return .nil }
            if name == "T" { return .bool(true) }
            if name == "selection" {
                return try parseSelectionExpression()
            }
            return .symbol(name)
        case .symbol("[", _, _):
            advance()
            var items: [FDExpr] = []
            if !matchSymbol("]") {
                repeat { items.append(try parseExpression()) } while matchSymbol(",")
                try expectSymbol("]")
            }
            return .list(items)
        case .symbol("(", _, _):
            advance()
            let expr = try parseExpression()
            try expectSymbol(")")
            return expr
        default:
            throw parseError("Expected expression, found \(tokenDescription(current))")
        }
    }

    func parseSelectionExpression() throws -> FDExpr {
        guard case let .identifier(mode, _, _) = current else {
            throw parseError("Expected selection mode (implied, crossing, window, prompt), found \(tokenDescription(current))")
        }
        advance()
        switch mode {
        case "implied":
            return .call("ssget", [.string("_I")])
        case "crossing":
            return .call("ssget", [.string("_C"), try parseExpression(), try parseExpression()])
        case "window":
            return .call("ssget", [.string("_W"), try parseExpression(), try parseExpression()])
        case "prompt":
            return .call("ssget", [.string(try expectString())])
        default:
            throw parseError("Unknown selection mode '\(mode)'. Expected: implied, crossing, window, prompt")
        }
    }

    // MARK: - Function calls

    func parseFunctionCall(_ name: String) throws -> FDExpr {
        var args: [FDExpr] = []
        if !matchSymbol(")") {
            repeat { args.append(try parseExpression()) } while matchSymbol(",")
            try expectSymbol(")")
        }
        if name == "raw", args.count == 1, case let .string(s) = args[0] {
            return .call("raw", [.string(s)])
        }
        return .call(name, args)
    }

    // MARK: - Macro calls

    func parseMacroCall() throws -> FDStmt {
        guard case let .identifier(name, _, _) = current else {
            throw parseError("Expected macro name")
        }
        advance()
        let callerBody: [FDStmt]
        if case .symbol("{", _, _) = current {
            callerBody = try parseBlock()
        } else {
            callerBody = []
        }
        guard let bodyTokens = macros[name] else {
            throw parseError("Unknown macro '\(name)'")
        }
        guard expansionDepth < 50 else {
            throw parseError("Macro expansion limit exceeded while expanding '\(name)'")
        }
        let subParser = FieldDraftScriptParser(
            tokens: bodyTokens, macros: macros,
            yieldBody: callerBody, expansionDepth: expansionDepth + 1
        )
        let expanded = try subParser.parseMacroExpansion(yieldBody: callerBody)
        return expanded.isEmpty ? .raw("") : expanded.last!
    }
}
