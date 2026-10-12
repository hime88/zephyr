// VlRegistryBuiltins: Wave-C vl-registry-read/write/delete on
// UserDefaults. AutoCAD uses the Windows registry; Zephyr maps the
// same key/value contract onto UserDefaults so user settings persist.
//
// Contract from the registry oracle:
//   (vl-registry-read REGKEY [VALUE-NAME]) -> value or nil
//   (vl-registry-write REGKEY [VALUE-NAME] VALUE) -> VALUE
//   (vl-registry-delete REGKEY [VALUE-NAME]) -> T or nil
import Foundation

enum VlRegistryBuiltins {
    static let table: [String: LispBuiltin] = [
        "VL-REGISTRY-READ": vlRegistryRead,
        "VL-REGISTRY-WRITE": vlRegistryWrite,
        "VL-REGISTRY-DELETE": vlRegistryDelete,
        "VL-ACAD-DEFUN": vlAcadDefun,
        "VL-DOC-EXPORT": vlDocExport,
        "VL-DOC-IMPORT": vlDocImport,
        "VLA-STARTUNDOMARK": vlaStartUndoMark,
        "VLA-ENDUNDOMARK": vlaEndUndoMark,
    ]

    /// All Lisp registry keys are namespaced so they never collide
    /// with host app preferences.
    static let namespace = "ZephyrLispRegistry."

    private static func storageKey(_ regKey: String, _ valueName: String?) -> String {
        if let valueName, !valueName.isEmpty {
            return "\(namespace)\(regKey).\(valueName)"
        }
        return "\(namespace)\(regKey)"
    }

    private static func decode(_ object: Any) -> LispValue? {
        switch object {
        case let value as String:
            return .string(value)
        case let value as Int:
            return .int(value)
        case let value as Double:
            return .real(value)
        case let value as Bool:
            return value ? .t : .nilValue
        case let value as [Any]:
            let items = value.compactMap { decode($0) }
            guard items.count == value.count else { return nil }
            return LispValue(list: items)
        default:
            return nil
        }
    }

    private static func encode(_ value: LispValue) -> Any? {
        switch value {
        case let .string(text):
            return text
        case let .int(number):
            return number
        case let .real(number):
            return number
        case let .symbol(name) where name == "T":
            return true
        case let .symbol(name) where name == "NIL":
            return false
        case .cons:
            guard let items = value.properList else { return nil }
            let encoded = items.compactMap { encode($0) }
            guard encoded.count == items.count else { return nil }
            return encoded
        default:
            return nil
        }
    }

    private static func vlRegistryRead(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.range("vl-registry-read", args, min: 1, max: 2)
        let regKey = try BuiltinArgs.string("vl-registry-read", args[0])
        var valueName: String?
        if args.count == 2 {
            valueName = try BuiltinArgs.string("vl-registry-read", args[1])
        }
        let stored = UserDefaults.standard.object(forKey: storageKey(regKey, valueName))
        guard let stored, let decoded = decode(stored) else { return .nilValue }
        return decoded
    }

    private static func vlRegistryWrite(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.range("vl-registry-write", args, min: 2, max: 3)
        let regKey = try BuiltinArgs.string("vl-registry-write", args[0])
        var valueName: String?
        var value: LispValue
        if args.count == 3 {
            valueName = try BuiltinArgs.string("vl-registry-write", args[1])
            value = args[2]
        } else {
            value = args[1]
        }
        guard let encoded = encode(value) else {
            throw LispError.typeMismatch(
                name: "vl-registry-write", expected: "STR/INT/REAL/T/list", got: value)
        }
        UserDefaults.standard.set(encoded, forKey: storageKey(regKey, valueName))
        return value
    }

    private static func vlRegistryDelete(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.range("vl-registry-delete", args, min: 1, max: 2)
        let regKey = try BuiltinArgs.string("vl-registry-delete", args[0])
        var valueName: String?
        if args.count == 2 {
            valueName = try BuiltinArgs.string("vl-registry-delete", args[1])
        }
        let key = storageKey(regKey, valueName)
        guard UserDefaults.standard.object(forKey: key) != nil else {
            return .nilValue
        }
        UserDefaults.standard.removeObject(forKey: key)
        return .t
    }

    /// vl-acad-defun registers a global function visible to every open
    /// document; with Zephyr's single-document model this is `defun`
    /// recorded in the persistent global frame.
    private static func vlAcadDefun(
        _: LispEvaluator, args: [LispValue], env: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.range("vl-acad-defun", args, min: 1, max: 2)
        let name = try BuiltinArgs.symbol("vl-acad-defun", args[0])
        env.globals[name] = args.count == 2 ? args[1] : .nilValue
        return .symbol(name)
    }

    /// Document scoping underpinnings for Tier 2. Zephyr is a
    /// single-document host, so export/import are identity operations
    /// over the caller's own symbol: export records a doc-scoped
    /// binding in the environment; import reads it back.
    private static func vlDocExport(
        _: LispEvaluator, args: [LispValue], env: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly("vl-doc-export", args, 1)
        let name = try BuiltinArgs.symbol("vl-doc-export", args[0])
        env.docScope[name] = env.globals[name] ?? .nilValue
        return .symbol(name)
    }

    private static func vlDocImport(
        _: LispEvaluator, args: [LispValue], env: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly("vl-doc-import", args, 1)
        let name = try BuiltinArgs.symbol("vl-doc-import", args[0])
        let value = env.docScope[name] ?? .nilValue
        env.globals[name] = value
        return .symbol(name)
    }

    /// ActiveX undo marks map onto the host undo groups from Step 3:
    /// STARTUNDOMARK opens a group, ENDUNDOMARK closes it.
    private static func vlaStartUndoMark(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, host: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.range("vla-startundomark", args, min: 0, max: 1)
        await host.beginUndoMark()
        return .nilValue
    }

    private static func vlaEndUndoMark(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, host: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.range("vla-endundomark", args, min: 0, max: 1)
        await host.endUndoMark()
        return .nilValue
    }
}
