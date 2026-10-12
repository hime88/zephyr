// SystemBuiltins: evaluation, application, display, loading, and identity.
//
// eval/apply/mapcar recurse through the evaluator; display builtins sink to
// the host; load/autoload manage file-backed definitions.

enum SystemBuiltins {
    static let table: [String: LispBuiltin] = [
        "EVAL": evalForm,
        "APPLY": apply,
        "MAPCAR": mapcar,
        "READ": read,
        "ATOMS-FAMILY": atomsFamily,
        "VL-SYMBOL-NAME": vlSymbolName,
        "VL-SYMBOL-VALUE": vlSymbolValue,
        "PRINC": princ,
        "PRIN1": prin1,
        "PRINT": printValue,
        "PROMPT": prompt,
        "TERPRI": terpri,
        "ALERT": alert,
        "LOAD": load,
        "AUTOLOAD": autoload,
        "VER": ver,
        "EXIT": quit,
        "QUIT": quit,
        "VLEXIT": quit,
        "TRACE": trace,
        "UNTRACE": untrace,
        "*POP-ERROR-MODE*": popErrorMode,
        "*PUSH-ERROR-USING-COMMAND*": pushErrorUsingCommand,
        "*PUSH-ERROR-USING-STACK*": pushErrorUsingStack,
        "VL-CATCH-ALL-APPLY": vlCatchAllApply,
        "VL-CATCH-ALL-ERROR-P": vlCatchAllErrorP,
        "VL-CATCH-ALL-ERROR-MESSAGE": vlCatchAllErrorMessage,
    ]

    // MARK: - Evaluation

    private static func evalForm(
        eval: LispEvaluator, args: [LispValue], env: inout LispEnvironment, host: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly("eval", args, 1)
        return try await eval.eval(args[0], env: &env, host: host, depth: 0)
    }

    private static func apply(
        eval: LispEvaluator, args: [LispValue], env: inout LispEnvironment, host: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.range("apply", args, min: 2)
        // (apply fn arg... arglist): trailing proper list spreads.
        guard let spread = args.last!.properList else {
            throw LispError.typeMismatch(name: "apply", expected: "argument list", got: args.last!)
        }
        let all = Array(args.dropFirst().dropLast()) + spread
        return try await eval.applyValue(args[0], args: all, env: &env, host: host, depth: 0)
    }

    private static func mapcar(
        eval: LispEvaluator, args: [LispValue], env: inout LispEnvironment, host: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.range("mapcar", args, min: 2)
        let lists = try args.dropFirst().map { try BuiltinArgs.properList("mapcar", $0) }
        let shortest = lists.map(\.count).min() ?? 0
        var out: [LispValue] = []
        for index in 0..<shortest {
            out.append(try await eval.applyValue(
                args[0], args: lists.map { $0[index] }, env: &env, host: host, depth: 0))
        }
        return LispValue(list: out)
    }

    private static func read(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, host: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.range("read", args, min: 0, max: 1)
        if args.isEmpty {
            guard let line = try await host.requestLine(prompt: "") else { return .nilValue }
            return try LispReader().readOne(line)
        }
        return try LispReader().readOne(try BuiltinArgs.string("read", args[0]))
    }

    private static func atomsFamily(
        _: LispEvaluator, args: [LispValue], env: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.range("atoms-family", args, min: 1, max: 2)
        _ = try BuiltinArgs.int("atoms-family", args[0]) // Format flag accepted.
        var names = Set(env.globals.keys).union(env.functions.keys)
        for frame in env.localsStack { names.formUnion(frame.keys) }
        if args.count == 2 {
            let wanted = Set(try BuiltinArgs.properList("atoms-family", args[1]).compactMap {
                if case let .symbol(s) = $0 { return s } else { return nil }
            })
            names.formIntersection(wanted)
        }
        return LispValue(list: names.sorted().map(LispValue.symbol))
    }

    private static func vlSymbolName(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly("vl-symbol-name", args, 1)
        return .string(try BuiltinArgs.symbol("vl-symbol-name", args[0]))
    }

    private static func vlSymbolValue(
        _: LispEvaluator, args: [LispValue], env: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly("vl-symbol-value", args, 1)
        let name = try BuiltinArgs.symbol("vl-symbol-value", args[0])
        return env.lookup(name) ?? .nilValue
    }

    // MARK: - Display (host sink)

    private static func princ(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, host: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.range("princ", args, min: 0, max: 1)
        guard let value = args.first else { return .nilValue }
        await host.write(value.displayString)
        return value
    }

    private static func prin1(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, host: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.range("prin1", args, min: 0, max: 1)
        guard let value = args.first else { return .nilValue }
        await host.write(value.prin1String)
        return value
    }

    private static func printValue(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, host: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.range("print", args, min: 0, max: 1)
        guard let value = args.first else {
            await host.write("\n")
            return .nilValue
        }
        await host.write("\n" + value.prin1String + " ")
        return value
    }

    private static func prompt(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, host: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly("prompt", args, 1)
        await host.write(try BuiltinArgs.string("prompt", args[0]))
        return .nilValue
    }

    private static func terpri(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, host: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly("terpri", args, 0)
        await host.write("\n")
        return .nilValue
    }

    private static func alert(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, host: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly("alert", args, 1)
        await host.alert(try BuiltinArgs.string("alert", args[0]))
        return .nilValue
    }

    // MARK: - Loading

    private static func load(
        eval: LispEvaluator, args: [LispValue], env: inout LispEnvironment, host: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.range("load", args, min: 1, max: 2)
        let path = try BuiltinArgs.string("load", args[0])
        do {
            return try await eval.load(path: path, env: &env, host: host)
        } catch {
            // (load file onfailure): return the fallback instead of throwing.
            if args.count == 2 { return args[1] }
            throw error
        }
    }

    private static func autoload(
        _: LispEvaluator, args: [LispValue], env: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly("autoload", args, 2)
        let path = try BuiltinArgs.string("autoload", args[0])
        let commands = try BuiltinArgs.properList("autoload", args[1])
        for command in commands {
            guard case let .string(name) = command else {
                throw LispError.typeMismatch(name: "autoload", expected: "command-name strings", got: command)
            }
            env.autoloadStubs[name.uppercased()] = path
        }
        return .nilValue
    }

    private static func ver(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly("ver", args, 0)
        return .string("ZephyrLisp 1.0.0 (AutoLISP-compatible)")
    }

    private static func quit(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        _ = args
        throw LispError.quitRequested
    }

    // MARK: - trace / untrace

    /// (trace fn...) marks user functions for entry/exit logging; the
    /// evaluator prints via host.write on each traced call. Returns the
    /// last symbol traced, or nil with no arguments.
    private static func trace(
        _: LispEvaluator, args: [LispValue], env: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.range("trace", args, min: 0)
        var last: LispValue = .nilValue
        for arg in args {
            let name = try BuiltinArgs.symbol("trace", arg)
            env.tracedFunctions.insert(name)
            last = .symbol(name)
        }
        return last
    }

    /// (untrace fn...) clears trace marks. Returns the last symbol
    /// untraced, or nil with no arguments.
    private static func untrace(
        _: LispEvaluator, args: [LispValue], env: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.range("untrace", args, min: 0)
        var last: LispValue = .nilValue
        for arg in args {
            let name = try BuiltinArgs.symbol("untrace", arg)
            env.tracedFunctions.remove(name)
            last = .symbol(name)
        }
        return last
    }

    // MARK: - *error* mode stack

    /// (*push-error-using-command*) records that the custom *error*
    /// handler issues (command ...) calls. Always returns nil.
    private static func pushErrorUsingCommand(
        _: LispEvaluator, args: [LispValue], env: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly("*push-error-using-command*", args, 0)
        env.errorModeStack.append("COMMAND")
        return .nilValue
    }

    /// (*push-error-using-stack*) records that the custom *error*
    /// handler reads AutoLISP stack variables. Always returns nil.
    private static func pushErrorUsingStack(
        _: LispEvaluator, args: [LispValue], env: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly("*push-error-using-stack*", args, 0)
        env.errorModeStack.append("STACK")
        return .nilValue
    }

    /// (*pop-error-mode*) ends the most recent push call. Always
    /// returns nil, even when the stack is empty.
    private static func popErrorMode(
        _: LispEvaluator, args: [LispValue], env: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly("*pop-error-mode*", args, 0)
        _ = env.errorModeStack.popLast()
        return .nilValue
    }

    // MARK: - vl-catch-all (catches everything except quit; skips *error*)

    private static func vlCatchAllApply(
        eval: LispEvaluator, args: [LispValue], env: inout LispEnvironment, host: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.range("vl-catch-all-apply", args, min: 2)
        guard let spread = args.last!.properList else {
            throw LispError.typeMismatch(
                name: "vl-catch-all-apply", expected: "argument list", got: args.last!)
        }
        let all = Array(args.dropFirst().dropLast()) + spread
        do {
            return try await eval.applyValue(args[0], args: all, env: &env, host: host, depth: 0)
        } catch let error as LispError {
            if error.isFatalToCatchAll { throw error }
            return .errorObject(error.description)
        }
    }

    private static func vlCatchAllErrorP(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly("vl-catch-all-error-p", args, 1)
        if case .errorObject = args[0] { return .t }
        return .nilValue
    }

    private static func vlCatchAllErrorMessage(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly("vl-catch-all-error-message", args, 1)
        guard case let .errorObject(message) = args[0] else {
            throw LispError.typeMismatch(
                name: "vl-catch-all-error-message", expected: "catch-all error object", got: args[0])
        }
        return .string(message)
    }
}
