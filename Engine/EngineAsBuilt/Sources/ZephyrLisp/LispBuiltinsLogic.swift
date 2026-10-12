// LogicBuiltins: identity, deep equality, and type predicates.
//
// eq is same-type value equality for immediates (lists have no identity, so
// (eq '(1) '(1)) is nil); equal is recursive with an optional real fuzz.

enum LogicBuiltins {
    static let table: [String: LispBuiltin] = [
        "EQ": eq,
        "EQUAL": equal,
        "NOT": not,
        "ATOM": atom,
        "LISTP": listp,
        "NULL": nullp,
        "TYPE": typeOf,
        "BOUNDP": boundp,
        "VL-SYMBOLP": vlSymbolp,
    ]

    // MARK: - Equality

    private static func eq(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly("eq", args, 2)
        return .tOrNil(shallowEqual(args[0], args[1]))
    }

    private static func equal(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.range("equal", args, min: 2, max: 3)
        let fuzz: Double? = {
            guard args.count == 3 else { return nil }
            return args[2].asDouble
        }()
        return .tOrNil(deepEqual(args[0], args[1], fuzz: fuzz))
    }

    /// eq semantics: same-type immediate equality. Values are value
    /// types here, so there is no observable object identity: two
    /// indistinguishable values must compare the same. The oracle pins
    /// aliased lists eq to T, so structurally equal values are eq
    /// (same-type strict, unlike equal's cross-numeric fuzz).
    static func shallowEqual(_ a: LispValue, _ b: LispValue) -> Bool {
        a == b
    }

    /// equal semantics: recursive; numbers compare across int/real; fuzz
    /// widens real comparison everywhere in the structure.
    static func deepEqual(_ a: LispValue, _ b: LispValue, fuzz: Double?) -> Bool {
        switch (a, b) {
        case (.nilValue, .nilValue): return true
        case let (.int(x), .int(y)): return x == y
        case (.int, .real), (.real, .int), (.real, .real):
            guard let x = a.asDouble, let y = b.asDouble else { return false }
            if let fuzz { return abs(x - y) <= abs(fuzz) }
            return x == y
        case let (.string(x), .string(y)): return x == y
        case let (.symbol(x), .symbol(y)): return x == y
        case let (.entityName(x), .entityName(y)): return x == y
        case let (.selectionSet(x), .selectionSet(y)): return x == y
        case let (.cons(ah, at), .cons(bh, bt)):
            return deepEqual(ah, bh, fuzz: fuzz) && deepEqual(at, bt, fuzz: fuzz)
        default: return false
        }
    }

    // MARK: - Predicates

    private static func not(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly("not", args, 1)
        return .tOrNil(!args[0].isTrue)
    }

    private static func atom(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly("atom", args, 1)
        return .tOrNil(args[0].isAtom)
    }

    private static func listp(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly("listp", args, 1)
        // nil is the empty list: both atom and list.
        if case .nilValue = args[0] { return .t }
        if case .cons = args[0] { return .t }
        return .nilValue
    }

    private static func nullp(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly("null", args, 1)
        return .tOrNil(args[0].isNil)
    }

    private static func typeOf(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly("type", args, 1)
        switch args[0] {
        case .nilValue: return .symbol("LIST")
        case .int: return .symbol("INT")
        case .real: return .symbol("REAL")
        case .string: return .symbol("STR")
        case .symbol: return .symbol("SYM")
        case .cons: return .symbol("LIST")
        case .entityName: return .symbol("ENAME")
        case .selectionSet: return .symbol("PICKSET")
        case .errorObject: return .symbol("LIST")
        case .vlaObject: return .symbol("VLA-OBJECT")
        }
    }

    private static func boundp(
        _: LispEvaluator, args: [LispValue], env: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly("boundp", args, 1)
        if args[0].isNil { return .t } // nil is always defined
        let name = try BuiltinArgs.symbol("boundp", args[0])
        // Bound means present, even when bound to nil.
        if env.globals[name] != nil { return .t }
        for frame in env.localsStack where frame[name] != nil { return .t }
        return .nilValue
    }

    private static func vlSymbolp(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly("vl-symbolp", args, 1)
        if case .symbol = args[0] { return .t }
        return .nilValue
    }
}
