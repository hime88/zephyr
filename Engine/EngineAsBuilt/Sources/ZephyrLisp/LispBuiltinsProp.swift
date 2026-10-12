// PropBuiltins: Wave-B property access + transforms + textbox
// (getpropertyvalue/setpropertyvalue/ispropertyreadonly/dumpallproperties/
// trans/textbox). All six are host-bound (drawing state); the scripted
// host reports no drawing.
enum PropBuiltins {
    static let table: [String: LispBuiltin] = [
        "GETPROPERTYVALUE": getpropertyvalue,
        "SETPROPERTYVALUE": setpropertyvalue,
        "ISPROPERTYREADONLY": ispropertyreadonly,
        "DUMPALLPROPERTIES": dumpallproperties,
        "TRANS": trans,
        "TEXTBOX": textbox,
    ]

    private static func ename(_ name: String, _ value: LispValue) throws -> String {
        guard case let .entityName(handle) = value else {
            throw LispError.typeMismatch(name: name, expected: "entity name", got: value)
        }
        return handle
    }

    private static func getpropertyvalue(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, host: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.range("getpropertyvalue", args, min: 2, max: 3)
        let handle = try ename("getpropertyvalue", args[0])
        let property = try BuiltinArgs.string("getpropertyvalue", args[1])
        let index = args.count == 3 ? try BuiltinArgs.int("getpropertyvalue", args[2]) : nil
        return try await host.propertyValue(handle, property: property, index: index)
    }

    private static func setpropertyvalue(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, host: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly("setpropertyvalue", args, 3)
        let handle = try ename("setpropertyvalue", args[0])
        let property = try BuiltinArgs.string("setpropertyvalue", args[1])
        return try await host.setPropertyValue(handle, property: property, value: args[2])
    }

    private static func ispropertyreadonly(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, host: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly("ispropertyreadonly", args, 2)
        let handle = try ename("ispropertyreadonly", args[0])
        let property = try BuiltinArgs.string("ispropertyreadonly", args[1])
        return try await host.isPropertyReadOnly(handle, property: property) ? .t : .nilValue
    }

    private static func dumpallproperties(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, host: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.range("dumpallproperties", args, min: 1, max: 2)
        let handle = try ename("dumpallproperties", args[0])
        try await host.dumpProperties(handle)
        return .t
    }

    private static func trans(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, host: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.range("trans", args, min: 3, max: 4)
        guard let point = args[0].asPoint, point.count >= 2 else {
            throw LispError.typeMismatch(name: "trans", expected: "point", got: args[0])
        }
        let from = args[1], to = args[2]
        for (label, value) in [("from", from), ("to", to)] {
            switch value {
            case .int, .real, .entityName: break
            default:
                throw LispError.typeMismatch(
                    name: "trans", expected: "\(label) coordinate system (0/1/ename)", got: value)
            }
        }
        let disp = args.count == 4 && args[3].isTrue
        let out = try await host.transPoint(point, from: from, to: to, disp: disp)
        return LispValue(list: out.map(LispValue.real))
    }

    private static func textbox(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, host: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly("textbox", args, 1)
        guard args[0].properList != nil else {
            throw LispError.typeMismatch(
                name: "textbox", expected: "entity data list", got: args[0])
        }
        return try await host.textBox(args[0]) ?? .nilValue
    }
}
