import FieldDraftScriptCore

// MARK: - Async Runtime Interpreter

public final class FDInterpreter: @unchecked Sendable {
    private let host: FDHost

    public init(host: FDHost) {
        self.host = host
    }

    // MARK: - Run

    public func run(_ program: FDProgram, command name: String? = nil) async throws {
        var env = FDEnvironment()
        for decl in program.declarations {
            if case let .function(fn) = decl { env.functions[fn.name] = fn }
        }
        if let name {
            guard let cmd = program.declarations.compactMap({ decl -> FDCommandDecl? in
                if case let .command(c) = decl, c.name == name { return c }
                return nil
            }).first else {
                throw FDRuntimeError.unknownCommand(name)
            }
            _ = try await evalBlock(cmd.body, env: &env)
            return
        }
        for decl in program.declarations {
            if case let .command(cmd) = decl {
                _ = try await evalBlock(cmd.body, env: &env)
            }
        }
    }

    // MARK: - Statement evaluation

    private func evalBlock(_ body: [FDStmt], env: inout FDEnvironment) async throws -> FDValue {
        var last: FDValue = .nilValue
        for stmt in body {
            last = try await eval(stmt, env: &env)
        }
        return last
    }

    private func eval(_ stmt: FDStmt, env: inout FDEnvironment) async throws -> FDValue {
        switch stmt {
        case .comment, .setup, .restore: return .nilValue
        case let .setq(pairs):
            var last: FDValue = .nilValue
            for (name, expr) in pairs {
                last = try await evalExpr(expr, env: &env)
                env.variables[name] = last
            }
            return last
        case let .setvar(name, expr):
            let value = try await evalExpr(expr, env: &env)
            return try await host.call("setvar", [.string(name), value], env: &env)
        case let .expr(expr):
            return try await evalExpr(expr, env: &env)
        case let .ifStmt(condition, then, elseBody):
            let cond = try await evalExpr(condition, env: &env)
            if isTruthy(cond) { return try await evalBlock(then, env: &env) }
            else if let elseBody { return try await evalBlock(elseBody, env: &env) }
            return .nilValue
        case let .ifLet(name, assignment, then, elseBody):
            let value = try await evalInput(assignment, env: &env)
            env.variables[name] = value
            if isTruthy(value) { return try await evalBlock(then, env: &env) }
            else if let elseBody { return try await evalBlock(elseBody, env: &env) }
            return .nilValue
        case let .whileStmt(condition, body):
            var last: FDValue = .nilValue
            while isTruthy(try await evalExpr(condition, env: &env)) {
                last = try await evalBlock(body, env: &env)
            }
            return last
        case let .cond(cases):
            for (cond, body) in cases {
                if isTruthy(try await evalExpr(cond, env: &env)) {
                    return try await evalBlock(body, env: &env)
                }
            }
            return .nilValue
        case let .repeat(countExpr, body):
            let count = try await evalExpr(countExpr, env: &env)
            guard case let .number(n) = count else { return .nilValue }
            var last: FDValue = .nilValue
            for _ in 0..<Int(n) { last = try await evalBlock(body, env: &env) }
            return last
        case let .foreach(name, listExpr, body):
            let listVal = try await evalExpr(listExpr, env: &env)
            guard case let .list(items) = listVal else { return .nilValue }
            var last: FDValue = .nilValue
            for item in items {
                env.variables[name] = item
                last = try await evalBlock(body, env: &env)
            }
            return last
        case let .returnStmt(expr):
            return try await evalExpr(expr, env: &env)
        case .raw:
            return .nilValue
        }
    }

    // MARK: - Expression evaluation

    private func evalExpr(_ expr: FDExpr, env: inout FDEnvironment) async throws -> FDValue {
        switch expr {
        case .nil: return .nilValue
        case let .bool(v): return .bool(v)
        case let .number(v): return .number(v)
        case let .string(v): return .string(v)
        case let .symbol(name):
            return env.variables[name] ?? .nilValue
        case let .list(items):
            var values: [FDValue] = []
            for item in items { values.append(try await evalExpr(item, env: &env)) }
            return .list(values)
        case let .call(name, args):
            var values: [FDValue] = []
            for arg in args { values.append(try await evalExpr(arg, env: &env)) }
            return try await host.call(name, values, env: &env)
        case let .unary(op, v):
            let val = try await evalExpr(v, env: &env)
            return try await host.call(op, [val], env: &env)
        case let .binary(op, l, r):
            let lhs = try await evalExpr(l, env: &env)
            let rhs = try await evalExpr(r, env: &env)
            return try await host.call(op, [lhs, rhs], env: &env)
        }
    }

    private func evalInput(_ input: FDInputExpr, env: inout FDEnvironment) async throws -> FDValue {
        switch input {
        case let .point(prompt, base):
            let baseVal: FDValue = base.flatMap { env.variables[$0] } ?? .nilValue
            return try await host.call("getpoint", [.string(prompt), baseVal], env: &env)
        case let .select(prompt):
            return try await host.call("entsel", [.string(prompt)], env: &env)
        }
    }

    // MARK: - Helpers

    private func isTruthy(_ value: FDValue) -> Bool {
        if case .nilValue = value { return false }
        if case let .bool(v) = value { return v }
        return true
    }
}
