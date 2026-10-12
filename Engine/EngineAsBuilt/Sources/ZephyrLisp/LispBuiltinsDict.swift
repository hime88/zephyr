// DictBuiltins: Wave-B named dictionaries + appids
// (dictadd/dictnext/dictremove/dictrename/dictsearch/namedobjdict/regapp).
//
// Session-local string-keyed dictionaries living in the environment (see
// LispEnvironment.dictionaries). namedobjdict answers an ENAME-typed handle
// ("NAMEDOBJDICT") so (type (namedobjdict)) reads ENAME; the dict functions
// accept that handle or a plain dictionary-name string. Dictionaries
// auto-create on first add. All names are case-insensitive (uppercased).
enum DictBuiltins {
    static let table: [String: LispBuiltin] = [
        "DICTADD": dictadd,
        "DICTNEXT": dictnext,
        "DICTREMOVE": dictremove,
        "DICTRENAME": dictrename,
        "DICTSEARCH": dictsearch,
        "NAMEDOBJDICT": namedobjdict,
        "REGAPP": regapp,
    ]

    private static func namedobjdict(
        _: LispEvaluator, args: [LispValue], env: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.range("namedobjdict", args, min: 0, max: 0)
        if env.dictionaries["NAMEDOBJDICT"] == nil {
            env.dictionaries["NAMEDOBJDICT"] = [:]
        }
        return .entityName("NAMEDOBJDICT")
    }

    /// Dictionary designator: ename handle or name string, uppercased.
    private static func dictName(_ name: String, _ value: LispValue) throws -> String {
        switch value {
        case let .entityName(handle): return handle.uppercased()
        case let .string(text): return text.uppercased()
        default:
            throw LispError.typeMismatch(
                name: name, expected: "dictionary name or handle", got: value)
        }
    }

    /// Entry key: symbol or string, uppercased.
    private static func entryKey(_ name: String, _ value: LispValue) throws -> String {
        switch value {
        case let .symbol(text): return text.uppercased()
        case let .string(text): return text.uppercased()
        default:
            throw LispError.typeMismatch(
                name: name, expected: "entry key symbol or string", got: value)
        }
    }

    private static func dictadd(
        _: LispEvaluator, args: [LispValue], env: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly("dictadd", args, 3)
        let dict = try dictName("dictadd", args[0])
        let key = try entryKey("dictadd", args[1])
        var entries = env.dictionaries[dict] ?? [:]
        entries[key] = args[2]
        env.dictionaries[dict] = entries
        return args[2]
    }

    private static func dictsearch(
        _: LispEvaluator, args: [LispValue], env: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.range("dictsearch", args, min: 2, max: 3)
        let dict = try dictName("dictsearch", args[0])
        let key = try entryKey("dictsearch", args[1])
        guard let entries = env.dictionaries[dict],
              let value = entries[key]
        else {
            return .nilValue
        }
        if args.count == 3, args[2].isTrue {
            // setnext: park the dictnext cursor after this entry.
            let keys = entries.keys.sorted()
            if let index = keys.firstIndex(of: key) {
                env.dictCursors[dict] = index + 1
            }
        }
        // Entry shape: ((3 . key) (350 . value)).
        return LispValue(list: [
            .cons(head: .int(3), tail: .string(key)),
            .cons(head: .int(350), tail: value),
        ])
    }

    private static func dictnext(
        _: LispEvaluator, args: [LispValue], env: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.range("dictnext", args, min: 1, max: 2)
        let dict = try dictName("dictnext", args[0])
        let entries = env.dictionaries[dict] ?? [:]
        let keys = entries.keys.sorted()
        var cursor = env.dictCursors[dict] ?? 0
        if args.count == 2, args[1].isTrue {
            cursor = 0 // rewind, then fall through to return the first entry
        }
        guard cursor < keys.count else {
            env.dictCursors[dict] = 0
            return .nilValue
        }
        let key = keys[cursor]
        env.dictCursors[dict] = cursor + 1
        return .cons(head: .string(key), tail: entries[key] ?? .nilValue)
    }

    private static func dictremove(
        _: LispEvaluator, args: [LispValue], env: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly("dictremove", args, 2)
        let dict = try dictName("dictremove", args[0])
        let key = try entryKey("dictremove", args[1])
        guard var entries = env.dictionaries[dict],
              let removed = entries.removeValue(forKey: key)
        else {
            return .nilValue
        }
        env.dictionaries[dict] = entries
        return removed
    }

    private static func dictrename(
        _: LispEvaluator, args: [LispValue], env: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly("dictrename", args, 3)
        let dict = try dictName("dictrename", args[0])
        let old = try entryKey("dictrename", args[1])
        let new = try entryKey("dictrename", args[2])
        guard var entries = env.dictionaries[dict],
              let value = entries[old],
              entries[new] == nil
        else {
            return .nilValue
        }
        entries.removeValue(forKey: old)
        entries[new] = value
        env.dictionaries[dict] = entries
        return value
    }

    private static func regapp(
        _: LispEvaluator, args: [LispValue], env: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly("regapp", args, 1)
        let name: String
        switch args[0] {
        case let .string(text): name = text
        case let .symbol(text): name = text
        default:
            throw LispError.typeMismatch(
                name: "regapp", expected: "application name string", got: args[0])
        }
        // Appids are non-empty with no whitespace.
        guard !name.isEmpty,
              name.rangeOfCharacter(from: .whitespacesAndNewlines) == nil
        else {
            return .nilValue
        }
        env.appIDs.insert(name.uppercased())
        return .string(name)
    }
}
