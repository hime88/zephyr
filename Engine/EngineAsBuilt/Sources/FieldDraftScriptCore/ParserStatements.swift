// MARK: - Statement Parsing

extension FieldDraftScriptParser {

    func parseStatement() throws -> FDStmt {
        // Check for macro call first
        if case let .identifier(value, _, _) = current, macros[value] != nil {
            return try parseMacroCall()
        }

        if matchIdentifier("setup") { return .setup }
        if matchIdentifier("restore") { return .restore }
        if matchIdentifier("comment") { return .comment(try expectString()) }
        if matchIdentifier("setq") { return try parseSetqStatement() }
        if matchIdentifier("setvar") { return try parseSetvarStatement() }
        if matchIdentifier("princ") { return try parsePrincStatement() }
        if matchIdentifier("acadCommand") { return try parseAcadCommand() }
        if matchIdentifier("if") { return try parseIfStatement() }
        if matchIdentifier("ifLet") { return try parseIfLetStatement() }
        if matchIdentifier("while") { return try parseWhileStatement() }
        if matchIdentifier("cond") { return try parseCondStatement() }
        if matchIdentifier("repeat") { return try parseRepeatStatement() }
        if matchIdentifier("foreach") { return try parseForeachStatement() }
        if matchIdentifier("return") { return .returnStmt(try parseExpression()) }
        if matchIdentifier("selection") { return .expr(try parseSelectionExpression()) }
        if matchIdentifier("yield") {
            guard let yieldBody else { throw parseError("'yield' can only be used inside a macro expansion") }
            return yieldBody.isEmpty ? .raw("") : yieldBody.last!
        }
        // Door helpers, angles, textSelect — handle as fallthrough
        if matchIdentifier("doorPoints") {
            _ = try parseBlock() // skip body for now
            return .raw("") // placeholder, will be handled by AutoLISP backend
        }
        if matchIdentifier("textSelect") {
            _ = try expectIdentifier()
            _ = try expectString()
            _ = try parseBlock()
            if matchIdentifier("else") { _ = try parseBlock() }
            return .raw("") // placeholder
        }
        if matchIdentifier("normalizeSignedAngle") || matchIdentifier("normalizeAngle") {
            _ = try expectIdentifier()
            return .raw("") // placeholder
        }
        if matchIdentifier("drawDoorPanel") {
            _ = try expectIdentifier(); _ = try expectIdentifier()
            _ = try expectIdentifier(); _ = try expectIdentifier()
            return .raw("") // placeholder
        }
        if matchIdentifier("drawDoorArc") {
            _ = try expectIdentifier(); _ = try expectIdentifier()
            _ = try expectIdentifier(); _ = try expectIdentifier()
            return .raw("") // placeholder
        }

        // Unknown statement / expression fallthrough
        if case let .identifier(name, _, _) = current {
            advance()
            skipNewlines()
            if matchSymbol("(") {
                return .expr(try parseFunctionCall(name))
            }
            if let suggestion = statementSuggestion(for: name) {
                throw parseError("Unknown statement '\(name)'. Did you mean '\(suggestion)'?")
            }
            throw parseError("Unknown statement, found identifier '\(name)'")
        }
        throw parseError("Unknown statement, found \(tokenDescription(current))")
    }

    func parseSetqStatement() throws -> FDStmt {
        if matchSymbol("{") {
            var pairs: [(String, FDExpr)] = []
            skipNewlines()
            while !matchSymbol("}") {
                if isEOF { throw parseError("Expected '}' before end of file") }
                if case .comment = current { advance(); skipNewlines(); continue }
                let name = try expectIdentifier()
                try expectSymbol("=")
                pairs.append((name, try parseExpression()))
                if case .comment = current { advance() }
                skipNewlines()
            }
            return .setq(pairs)
        }
        let name = try expectIdentifier()
        try expectSymbol("=")
        return .setq([(name, try parseExpression())])
    }

    func parseSetvarStatement() throws -> FDStmt {
        let varName: String
        switch current {
        case let .string(value, _, _): varName = value; advance()
        case let .identifier(value, _, _): varName = value; advance()
        default: throw parseError("Expected setvar variable name, found \(tokenDescription(current))")
        }
        return .setvar(varName, try parseExpression())
    }

    func parsePrincStatement() throws -> FDStmt {
        if matchSymbol("(") {
            let expr = try parseExpression()
            try expectSymbol(")")
            return .expr(.call("princ", [expr]))
        }
        return .expr(.call("princ", [try parseExpression()]))
    }

    func parseAcadCommand() throws -> FDStmt {
        try expectSymbol("(")
        var args: [FDExpr] = []
        if !matchSymbol(")") {
            repeat { args.append(try parseExpression()) } while matchSymbol(",")
            try expectSymbol(")")
        }
        return .expr(.call("command", args))
    }

    func parseIfStatement() throws -> FDStmt {
        let condition = try parseExpression()
        let then = try parseBlock()
        let elseBody: [FDStmt]?
        skipNewlines()
        if matchIdentifier("else") { elseBody = try parseBlock() }
        else { elseBody = nil }
        return .ifStmt(condition: condition, then: then, elseBody: elseBody)
    }

    func parseIfLetStatement() throws -> FDStmt {
        let name = try expectIdentifier(context: "variable name for ifLet")
        try expectSymbol("=")
        let kind = try expectIdentifier(context: "assignment kind for ifLet")
        let input: FDInputExpr
        if kind == "point" {
            let message = try expectString()
            var base: String? = nil
            if matchIdentifier("base") { base = try expectIdentifier(context: "base point variable") }
            input = .point(prompt: message, base: base)
        } else if kind == "select" {
            input = .select(prompt: try expectString())
        } else {
            throw parseError("Expected ifLet assignment kind 'point' or 'select', found '\(kind)'")
        }
        let then = try parseBlock()
        let elseBody: [FDStmt]?
        skipNewlines()
        if matchIdentifier("else") { elseBody = try parseBlock() }
        else { elseBody = nil }
        return .ifLet(name: name, assignment: input, then: then, elseBody: elseBody)
    }

    func parseWhileStatement() throws -> FDStmt {
        .whileStmt(condition: try parseExpression(), body: try parseBlock())
    }

    func parseCondStatement() throws -> FDStmt {
        try expectSymbol("{")
        skipNewlines()
        var cases: [(FDExpr, [FDStmt])] = []
        while !matchSymbol("}") {
            if isEOF { throw parseError("Expected '}' before end of file") }
            if case .comment = current { advance(); skipNewlines(); continue }
            if matchIdentifier("else") {
                cases.append((.bool(true), try parseBlock()))
            } else {
                cases.append((try parseExpression(), try parseBlock()))
            }
            skipNewlines()
        }
        return .cond(cases)
    }

    func parseRepeatStatement() throws -> FDStmt {
        .repeat(try parseExpression(), try parseBlock())
    }

    func parseForeachStatement() throws -> FDStmt {
        let variable = try expectIdentifier(context: "loop variable for foreach")
        _ = try expectIdentifier("in", context: "'in' in foreach")
        return .foreach(name: variable, list: try parseExpression(), body: try parseBlock())
    }
}
