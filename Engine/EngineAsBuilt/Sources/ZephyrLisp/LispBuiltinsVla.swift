// VlaBuiltins: the minimal ActiveX underpinning (step 3).
//
// The seed corpus's entire Tier-2 surface is four functions: vl-load-com
// (called for effect at the top of every file), vlax-ename->vla-object,
// vla-getboundingbox (via vl-catch-all-apply with quoted out-symbols), and
// vlax-safearray->list. These four are implemented for real — the bounding
// box is computed from entity geometry — while the rest of vla-*/vlax-*
// stays deferred Tier 2. None of the four are in the 305-entry inventory;
// they are documented extensions pinned by LispVlaTests.

enum VlaBuiltins {
    static let table: [String: LispBuiltin] = [
        "VL-LOAD-COM": vlLoadCom,
        "VLAX-ENAME->VLA-OBJECT": vlaxEnameToVlaObject,
        "VLA-GETBOUNDINGBOX": vlaGetBoundingBox,
        "VLAX-SAFEARRAY->LIST": vlaxSafearrayToList,
    ]

    /// (vl-load-com): ActiveX startup hook. Zephyr has no COM runtime, so
    /// this is a no-op returning T — scripts call it defensively.
    private static func vlLoadCom(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.range("vl-load-com", args, min: 0, max: 0)
        return .t
    }

    private static func vlaxEnameToVlaObject(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly("vlax-ename->vla-object", args, 1)
        switch args[0] {
        case let .entityName(handle): return .vlaObject(handle)
        case .vlaObject: return args[0] // Idempotent.
        default:
            throw LispError.typeMismatch(
                name: "vlax-ename->vla-object",
                expected: "entity name", got: args[0])
        }
    }

    /// (vla-getboundingbox obj 'minSym 'maxSym): binds the two out-symbols
    /// to 3D point lists and returns T. Throws when the entity is unknown
    /// (callers use vl-catch-all-apply and test the symbols after).
    private static func vlaGetBoundingBox(
        _: LispEvaluator, args: [LispValue], env: inout LispEnvironment, host: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly("vla-getboundingbox", args, 3)
        let handle: String
        switch args[0] {
        case let .vlaObject(h): handle = h
        case let .entityName(h): handle = h // Lenient: bare enames work too.
        default:
            throw LispError.typeMismatch(
                name: "vla-getboundingbox",
                expected: "VLA-OBJECT", got: args[0])
        }
        let minSym = try BuiltinArgs.symbol("vla-getboundingbox", args[1])
        let maxSym = try BuiltinArgs.symbol("vla-getboundingbox", args[2])
        let box = try await host.vlaBoundingBox(handle)
        _ = try env.assign(minSym, LispValue(list: box.min.map(LispValue.real)))
        _ = try env.assign(maxSym, LispValue(list: box.max.map(LispValue.real)))
        return .t
    }

    /// (vlax-safearray->list arr): Zephyr safearrays ARE lists (see
    /// vla-getboundingbox), so this validates and returns its argument.
    private static func vlaxSafearrayToList(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly("vlax-safearray->list", args, 1)
        guard args[0].properList != nil else {
            throw LispError.typeMismatch(
                name: "vlax-safearray->list",
                expected: "safearray (list)", got: args[0])
        }
        return args[0]
    }
}
