// TableBuiltins: Wave-B symbol tables + layouts + ssnamex
// (tblnext/tblsearch/tblobjname/layoutlist/ssnamex).
//
// Drawing tables (LAYER/LTYPE/STYLE/BLOCK) come from the host; the APPID
// table reads the session's regapp set directly from the environment.
// tblobjname answers nil: table entries are data, not database objects,
// so there is no ename to return (use tblsearch for the entry content).
enum TableBuiltins {
    static let table: [String: LispBuiltin] = [
        "TBLNEXT": tblnext,
        "TBLSEARCH": tblsearch,
        "TBLOBJNAME": tblobjname,
        "LAYOUTLIST": layoutlist,
        "SSNAMEX": ssnamex,
    ]

    private static func tblnext(
        _: LispEvaluator, args: [LispValue], env: inout LispEnvironment, host: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.range("tblnext", args, min: 1, max: 2)
        let table = try BuiltinArgs.string("tblnext", args[0]).uppercased()
        let rewind = args.count == 2 && args[1].isTrue
        if table == "APPID" {
            return appidNext(env: &env, rewind: rewind)
        }
        return try await host.tableNext(table, rewind: rewind) ?? .nilValue
    }

    private static func tblsearch(
        _: LispEvaluator, args: [LispValue], env: inout LispEnvironment, host: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.range("tblsearch", args, min: 2, max: 3)
        let table = try BuiltinArgs.string("tblsearch", args[0]).uppercased()
        let name = try BuiltinArgs.string("tblsearch", args[1])
        let setNext = args.count == 3 && args[2].isTrue
        if table == "APPID" {
            return appidSearch(name: name, setNext: setNext, env: &env)
        }
        return try await host.tableSearch(table, name: name, setNext: setNext) ?? .nilValue
    }

    private static func tblobjname(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly("tblobjname", args, 2)
        _ = try BuiltinArgs.string("tblobjname", args[0])
        _ = try BuiltinArgs.string("tblobjname", args[1])
        // Table entries are not database objects: no ename exists.
        return .nilValue
    }

    private static func layoutlist(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, host: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.range("layoutlist", args, min: 0, max: 0)
        return LispValue(stringList: await host.layoutNames())
    }

    private static func ssnamex(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, host: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly("ssnamex", args, 2)
        guard case let .selectionSet(id) = args[0] else {
            throw LispError.typeMismatch(
                name: "ssnamex", expected: "selection set", got: args[0])
        }
        return try await host.ssNameX(id, index: BuiltinArgs.int("ssnamex", args[1]))
    }

    // MARK: - APPID table (session regapp set)

    private static func appidNext(env: inout LispEnvironment, rewind: Bool) -> LispValue {
        let names = env.appIDs.sorted()
        var cursor = env.dictCursors["APPID"] ?? 0
        if rewind { cursor = 0 }
        guard cursor < names.count else {
            env.dictCursors["APPID"] = 0
            return .nilValue
        }
        env.dictCursors["APPID"] = cursor + 1
        return appidEntry(names[cursor])
    }

    private static func appidSearch(
        name: String, setNext: Bool, env: inout LispEnvironment
    ) -> LispValue {
        let upper = name.uppercased()
        guard env.appIDs.contains(upper) else { return .nilValue }
        if setNext {
            let names = env.appIDs.sorted()
            if let index = names.firstIndex(of: upper) {
                env.dictCursors["APPID"] = index + 1
            }
        }
        return appidEntry(upper)
    }

    private static func appidEntry(_ name: String) -> LispValue {
        LispValue(list: [
            .cons(head: .int(0), tail: .string("APPID")),
            .cons(head: .int(2), tail: .string(name)),
            .cons(head: .int(70), tail: .int(0)),
        ])
    }
}
