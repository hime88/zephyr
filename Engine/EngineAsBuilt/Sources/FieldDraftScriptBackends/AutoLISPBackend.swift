import Foundation
import FieldDraftScriptCore

// MARK: - AutoLISP Backend

public struct AutoLISPBackend: FDTextBackend {
    public init() {}
    public func emit(_ program: FDProgram) throws -> String {
        program.declarations.map(emitDecl).joined(separator: "\n\n")
    }

    // MARK: - Declarations

    private func emitDecl(_ decl: FDDecl) -> String {
        switch decl {
        case let .command(cmd): return emitCommand(cmd)
        case let .function(fn): return emitFunction(fn)
        case let .alias(alias): return emitAlias(alias)
        case let .rawTop(code): return code
        }
    }

    private func emitCommand(_ decl: FDCommandDecl) -> String {
        let env = LispEnvironment()
        let renderedBody = emitBlock(decl.body, env: env)
        let locals = env.localVariables.isEmpty ? "" : "/ " + env.localVariables.sorted().joined(separator: " ")
        let completeBody = "(vl-load-com)\n" + renderedBody + "\n(princ)"
        return ";;; Compiled FieldDraft Script\n(defun c:\(decl.name) ( \(locals) )\n\(completeBody.indent())\n)"
    }

    private func emitFunction(_ decl: FDFunctionDecl) -> String {
        let env = LispEnvironment()
        for param in decl.params { env.localVariables.insert(param) }
        let renderedBody = emitBlock(decl.body, env: env)
        let locals = env.localVariables.subtracting(Set(decl.params)).sorted().joined(separator: " ")
        let localsPart = locals.isEmpty ? "" : " / \(locals)"
        let paramsStr = decl.params.joined(separator: " ")
        return "(defun \(decl.name) (\(paramsStr)\(localsPart))\n\(renderedBody.indent()))"
    }

    private func emitAlias(_ decl: FDAliasDecl) -> String {
        "(defun c:\(decl.alias) () (c:\(decl.target)))"
    }

    // MARK: - Statements

    private func emitBlock(_ body: [FDStmt], env: LispEnvironment) -> String {
        body.map { emitStmt($0, env: env) }.joined(separator: "\n")
    }

    private func emitStmt(_ stmt: FDStmt, env: LispEnvironment) -> String {
        switch stmt {
        case let .comment(text): return text.isEmpty ? "" : ";; \(text)"
        case .setup: return emitSetup(env: env)
        case .restore: return emitRestore(env: env)
        case let .setq(pairs):
            for (name, _) in pairs { env.localVariables.insert(name) }
            return emitSetq(pairs)
        case let .setvar(name, expr): return "(setvar \"\(name)\" \(emitExpr(expr)))"
        case let .expr(expr): return emitExpr(expr)
        case let .ifStmt(condition, then, elseBody):
            return emitIf(condition: condition, then: then, elseBody: elseBody, env: env)
        case let .ifLet(name, assignment, then, elseBody):
            return emitIfLet(name: name, assignment: assignment, then: then, elseBody: elseBody, env: env)
        case let .whileStmt(condition, body):
            return emitWhile(condition: condition, body: body, env: env)
        case let .cond(cases): return emitCond(cases, env: env)
        case let .repeat(count, body): return emitRepeat(count: count, body: body, env: env)
        case let .foreach(name, list, body): return emitForeach(name: name, list: list, body: body, env: env)
        case let .returnStmt(expr): return emitExpr(expr)
        case let .raw(code): return code
        }
    }

    // MARK: - Setup / Restore

    private func emitSetup(env: LispEnvironment) -> String {
        env.localVariables.insert("oldOs")
        env.localVariables.insert("oldCmd")
        env.localVariables.insert("*error*")
        return """
        ;; 1. Store current environmental variables
        (setq oldOs (getvar "OSMODE")
              oldCmd (getvar "CMDECHO"))
        (setvar "CMDECHO" 0)
        ;; 2. Define Custom Error Handler (Catches "Esc" and failures)
        (defun *error* (msg)
          (if oldOs (setvar "OSMODE" oldOs))
          (if oldCmd (setvar "CMDECHO" oldCmd))
          (princ "\\nCommand cancelled. Snap settings restored.")
          (princ)
        )
        """
    }

    private func emitRestore(env: LispEnvironment) -> String {
        """
        ;; 4. Standard Restore (If command finishes successfully)
        (setvar "OSMODE" oldOs)
        (setvar "CMDECHO" oldCmd)
        """
    }

    // MARK: - Control flow

    private func emitSetq(_ pairs: [(String, FDExpr)]) -> String {
        guard let first = pairs.first else { return "(setq)" }
        if pairs.count == 1 {
            return "(setq \(first.0) \(emitExpr(first.1)))"
        }
        let rest = pairs.dropFirst().map { "      \($0.0) \(emitExpr($0.1))" }.joined(separator: "\n")
        return "(setq \(first.0) \(emitExpr(first.1))\n\(rest))"
    }

    private func emitIf(condition: FDExpr, then: [FDStmt], elseBody: [FDStmt]?, env: LispEnvironment) -> String {
        let cond = emitExpr(condition)
        let tBlock = emitBranch(then)
        if let elseBody {
            let fBlock = emitBranch(elseBody)
            return "(if \(cond)\n\(tBlock.indent())\n\(fBlock.indent())\n)"
        }
        return "(if \(cond)\n\(tBlock.indent())\n)"
    }

    private func emitIfLet(name: String, assignment: FDInputExpr, then: [FDStmt], elseBody: [FDStmt]?, env: LispEnvironment) -> String {
        env.localVariables.insert(name)
        let setq: String = {
            switch assignment {
            case let .point(prompt, base):
                let bp = base.map { "\($0) " } ?? ""
                return "(setq \(name) (getpoint \(bp)\"\\n\(prompt)\"))"
            case let .select(prompt):
                return "(setq \(name) (car (entsel \"\\n\(prompt)\")))"
            }
        }()
        let tBlock = emitBranch(then)
        if let elseBody {
            let fBlock = emitBranch(elseBody)
            return "(if \(setq)\n\(tBlock.indent())\n\(fBlock.indent())\n)"
        }
        return "(if \(setq)\n\(tBlock.indent())\n)"
    }

    private func emitWhile(condition: FDExpr, body: [FDStmt], env: LispEnvironment) -> String {
        let cond = emitExpr(condition)
        let bodyStr = emitBlock(body, env: LispEnvironment())
        return "(while \(cond)\n\(bodyStr.indent())\n)"
    }

    private func emitCond(_ cases: [(FDExpr, [FDStmt])], env: LispEnvironment) -> String {
        let renderedCases = cases.map { (cond, body) in
            let condStr = emitExpr(cond)
            let bodyStr = emitBlock(body, env: LispEnvironment())
            return "(\(condStr)\n\(bodyStr.indent()))"
        }.joined(separator: "\n")
        return "(cond\n\(renderedCases.indent())\n)"
    }

    private func emitRepeat(count: FDExpr, body: [FDStmt], env: LispEnvironment) -> String {
        let countStr = emitExpr(count)
        let bodyStr = emitBranch(body)
        return "(repeat \(countStr)\n\(bodyStr.indent())\n)"
    }

    private func emitForeach(name: String, list: FDExpr, body: [FDStmt], env: LispEnvironment) -> String {
        env.localVariables.insert(name)
        let listStr = emitExpr(list)
        let bodyStr = emitBranch(body)
        return "(foreach \(name) \(listStr)\n\(bodyStr.indent())\n)"
    }

    private func emitBranch(_ stmts: [FDStmt]) -> String {
        let flat = stmts.compactMap { stmt -> String? in
            let s = emitStmt(stmt, env: LispEnvironment())
            return s.isEmpty ? nil : s
        }
        if flat.count == 1 { return flat[0] }
        let rendered = flat.joined(separator: "\n")
        return "(progn\n\(rendered.indent())\n)"
    }

    // MARK: - Expressions

    func emitExpr(_ expr: FDExpr) -> String {
        switch expr {
        case .nil: return "nil"
        case let .bool(v): return v ? "T" : "nil"
        case let .number(v):
            if Foundation.floor(v) == v, v <= Double(Int.max), v >= Double(Int.min) {
                return String(Int(v))
            }
            return String(v)
        case let .string(v): return "\"\(v)\""
        case let .symbol(v): return v
        case let .list(items):
            if items.isEmpty { return "'()" }
            return "(list " + items.map(emitExpr).joined(separator: " ") + ")"
        case let .call(name, args): return emitCall(name, args)
        case let .unary(op, v): return "(\(op) \(emitExpr(v)))"
        case let .binary(op, l, r):
            let lispOp = op == "==" ? "=" : op == "!=" ? "/=" : op
            return "(\(lispOp) \(emitExpr(l)) \(emitExpr(r)))"
        }
    }

    private func emitCall(_ name: String, _ args: [FDExpr]) -> String {
        let mappedName = mapFunctionName(name)
        let renderedArgs = args.map(emitExpr)

        if name == "getLocation", args.count == 1 {
            return "(cdr (assoc 10 (entget \(renderedArgs[0]))))"
        }
        if name == "dictSet", args.count >= 2 {
            let rest = renderedArgs.dropFirst().joined(separator: " ")
            return "(set (read (strcat \(renderedArgs[0]) \(rest))) \(renderedArgs.last ?? "nil"))"
        }
        if name == "dictHas", args.count >= 1 {
            return "(boundp (read (strcat \(renderedArgs.joined(separator: " ")))))"
        }
        if name == "dictGet", args.count >= 1 {
            return "(eval (read (strcat \(renderedArgs.joined(separator: " ")))))"
        }
        if name == "symName" {
            return "(strcat \(renderedArgs.map { maybeItoa($0) }.joined(separator: " ")))"
        }
        if name == "symRead" {
            return "(read (strcat \(renderedArgs.map { maybeItoa($0) }.joined(separator: " "))))"
        }
        if name == "symGet" {
            return "(eval (read (strcat \(renderedArgs.map { maybeItoa($0) }.joined(separator: " ")))))"
        }
        if name == "symBound" {
            return "(boundp (read (strcat \(renderedArgs.map { maybeItoa($0) }.joined(separator: " ")))))"
        }
        if name == "symClear" {
            return "(set (read (strcat \(renderedArgs.map { maybeItoa($0) }.joined(separator: " ")))) nil)"
        }
        if name == "symSet", args.count >= 2 {
            let nameArgs = Array(renderedArgs.dropLast())
            return "(set (read (strcat \(nameArgs.map { maybeItoa($0) }.joined(separator: " ")))) \(renderedArgs.last!))"
        }
        if mappedName == "list" && args.isEmpty { return "'()" }

        return renderedArgs.isEmpty ? "(\(mappedName))" : "(\(mappedName) \(renderedArgs.joined(separator: " ")))"
    }

    private func mapFunctionName(_ name: String) -> String {
        switch name {
        case "vlaxEnameToVlaObject": return "vlax-ename->vla-object"
        case "vlaxSafearrayToList": return "vlax-safearray->list"
        case "vlaGetBoundingBox": return "vla-getboundingbox"
        case "vlCatchAllApply": return "vl-catch-all-apply"
        case "onePlus": return "1+"
        case "oneMinus": return "1-"
        case "appendList": return "append"
        case "type_": return "type"
        case "print_": return "print"
        case "exit_": return "exit"
        case "quit_": return "quit"
        case "bitNot": return "~"
        default: return name
        }
    }

    private func maybeItoa(_ rendered: String) -> String {
        let indexNames: Set<String> = ["i", "idx", "ix", "iy", "gx", "gy", "k", "n", "m"]
        return indexNames.contains(rendered) ? "(itoa \(rendered))" : rendered
    }
}
