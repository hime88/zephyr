// VlSessionBuiltins: Wave-C session/document leftovers —
// defun-q-list-ref/set, acad-push/pop-dbmod, vl-doc-ref/set,
// vl-acad-undefun, vl-exit-with-error/value, vl-registry-descendents.
import Foundation

enum VlSessionBuiltins {
    static let table: [String: LispBuiltin] = [
        "DEFUN-Q-LIST-REF": defunQListRef,
        "DEFUN-Q-LIST-SET": defunQListSet,
        "ACAD-PUSH-DBMOD": acadPushDbmod,
        "ACAD-POP-DBMOD": acadPopDbmod,
        "VL-DOC-REF": vlDocRef,
        "VL-DOC-SET": vlDocSet,
        "VL-ACAD-UNDEFUN": vlAcadUndefun,
        "VL-EXIT-WITH-ERROR": vlExitWithError,
        "VL-EXIT-WITH-VALUE": vlExitWithValue,
        "VL-REGISTRY-DESCENDENTS": vlRegistryDescendents,
    ]

    // MARK: - defun-q lists

    /// (defun-q-list-ref SYM [DOC]) returns the saved ((args) body...)
    /// definition list, or nil when SYM is not a defun-q function.
    /// The document argument is accepted and ignored (single-doc host).
    private static func defunQListRef(
        _: LispEvaluator, args: [LispValue], env: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.range("defun-q-list-ref", args, min: 1, max: 2)
        let name = try BuiltinArgs.symbol("defun-q-list-ref", args[0])
        guard let fn = env.functions[name],
              let saved = fn.quotedForm,
              case let .cons(_, tail) = saved,
              let rest = tail.properList
        else {
            return .nilValue
        }
        return LispValue(list: rest)
    }

    /// (defun-q-list-set SYM ((args) body...) [DOC]) defines SYM from a
    /// definition list and returns SYM.
    private static func defunQListSet(
        _: LispEvaluator, args: [LispValue], env: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.range("defun-q-list-set", args, min: 2, max: 3)
        let name = try BuiltinArgs.symbol("defun-q-list-set", args[0])
        guard let parts = args[1].properList, !parts.isEmpty,
              let arglist = parts[0].properList
        else {
            throw LispError.typeMismatch(
                name: "defun-q-list-set", expected: "((args) body...)", got: args[1])
        }
        var params: [String] = []
        var locals: [String] = []
        var seenSlash = false
        for item in arglist {
            guard case let .symbol(param) = item else {
                throw LispError.typeMismatch(
                    name: "defun-q-list-set", expected: "parameter symbol", got: item)
            }
            if param == "/" {
                seenSlash = true
                continue
            }
            if seenSlash { locals.append(param) } else { params.append(param) }
        }
        let body = Array(parts.dropFirst())
        env.functions[name] = LispFunction(
            params: params, locals: locals, body: body,
            quotedForm: LispValue(list: [.symbol(name)] + parts))
        return .symbol(name)
    }

    // MARK: - dbmod

    /// (acad-push-dbmod) saves the session dbmod counter and clears
    /// it. Returns T (oracle + Visual LISP guide).
    private static func acadPushDbmod(
        _: LispEvaluator, args: [LispValue], env: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly("acad-push-dbmod", args, 0)
        env.dbmodStack.append(env.dbmod)
        env.dbmod = 0
        return .t
    }

    /// (acad-pop-dbmod) restores the most recently pushed dbmod value.
    /// T on success, nil when the stack is empty.
    private static func acadPopDbmod(
        _: LispEvaluator, args: [LispValue], env: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly("acad-pop-dbmod", args, 0)
        guard let restored = env.dbmodStack.popLast() else { return .nilValue }
        env.dbmod = restored
        return .t
    }

    // MARK: - doc scope

    private static func vlDocRef(
        _: LispEvaluator, args: [LispValue], env: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly("vl-doc-ref", args, 1)
        return env.docScope[try BuiltinArgs.symbol("vl-doc-ref", args[0])] ?? .nilValue
    }

    private static func vlDocSet(
        _: LispEvaluator, args: [LispValue], env: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly("vl-doc-set", args, 2)
        let name = try BuiltinArgs.symbol("vl-doc-set", args[0])
        env.docScope[name] = args[1]
        return args[1]
    }

    /// (vl-acad-undefun SYM) removes a user function definition;
    /// T when one existed, nil otherwise.
    private static func vlAcadUndefun(
        _: LispEvaluator, args: [LispValue], env: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly("vl-acad-undefun", args, 1)
        let name = try BuiltinArgs.symbol("vl-acad-undefun", args[0])
        guard env.functions.removeValue(forKey: name) != nil else {
            return .nilValue
        }
        return .t
    }

    // MARK: - early exit

    /// (vl-exit-with-error MSG) aborts with an error carrying MSG.
    private static func vlExitWithError(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly("vl-exit-with-error", args, 1)
        throw LispError.hostError(try BuiltinArgs.string("vl-exit-with-error", args[0]))
    }

    /// (vl-exit-with-value VAL) aborts evaluation; run() returns VAL.
    /// Fatal to vl-catch-all-apply, like quit.
    private static func vlExitWithValue(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly("vl-exit-with-value", args, 1)
        throw LispError.exitWithValue(args[0])
    }

    // MARK: - registry descendents

    /// (vl-registry-descendents REGKEY [VALUE-NAMES]) lists the immediate
    /// child segments under REGKEY: subkeys by default (children that
    /// have children of their own), value names when VALUE-NAMES is
    /// non-nil (children stored as exact keys). Sorted, or nil.
    private static func vlRegistryDescendents(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.range("vl-registry-descendents", args, min: 1, max: 2)
        let regKey = try BuiltinArgs.string("vl-registry-descendents", args[0])
        let valueNames = args.count == 2 && args[1].isTrue
        let prefix = "\(VlRegistryBuiltins.namespace)\(regKey)."
        let stored = UserDefaults.standard.dictionaryRepresentation().keys
        let rests = stored.compactMap { key -> String? in
            guard key.hasPrefix(prefix) else { return nil }
            let rest = String(key.dropFirst(prefix.count))
            return rest.isEmpty ? nil : rest
        }
        let parents = Set(rests.compactMap { rest -> String? in
            guard let dot = rest.firstIndex(of: ".") else { return nil }
            return String(rest[..<dot])
        })
        // A leaf that also parents deeper keys is a subkey, not a value.
        let leaves = Set(rests.filter { $0.firstIndex(of: ".") == nil })
            .subtracting(parents)
        let picked = (valueNames ? leaves : parents).sorted()
        guard !picked.isEmpty else { return .nilValue }
        return LispValue(stringList: picked)
    }
}
