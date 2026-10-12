// DialogBuiltins: Wave-C file + color dialogs — getfiled,
// acad_colordlg, acad_truecolordlg, acad_truecolorcli. Modal dialogs
// route to the host (nil = cancel/unavailable); the CLI true-color
// prompt parses typed input portably.
enum DialogBuiltins {
    static let table: [String: LispBuiltin] = [
        "GETFILED": getfiled,
        "ACAD_COLORDLG": acadColordlg,
        "ACAD_TRUECOLORDLG": acadTruecolordlg,
        "ACAD_TRUECOLORCLI": acadTruecolorcli,
    ]

    private static func getfiled(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, host: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly("getfiled", args, 4)
        let title = try BuiltinArgs.string("getfiled", args[0])
        let defaultPath = try BuiltinArgs.string("getfiled", args[1])
        let extensions = try BuiltinArgs.string("getfiled", args[2])
        let flags = try BuiltinArgs.int("getfiled", args[3])
        guard let picked = await host.requestFile(
            title: title, defaultPath: defaultPath,
            extensions: extensions, flags: flags)
        else {
            return .nilValue
        }
        return .string(picked)
    }

    /// (acad_colordlg default [flag]). Flag non-nil disables the
    /// ByLayer/ByBlock entries. Returns ACI 0-256 or nil.
    private static func acadColordlg(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, host: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.range("acad_colordlg", args, min: 1, max: 2)
        let defaultACI = try BuiltinArgs.int("acad_colordlg", args[0])
        let allowByLayer = !(args.count == 2 && args[1].isTrue)
        guard let picked = await host.requestColor(
            default: defaultACI, allowByLayer: allowByLayer)
        else {
            return .nilValue
        }
        return .int(picked)
    }

    /// (acad_truecolordlg color [allowbylayer [currentlayercolor]]).
    /// The default is a dotted pair ((62 . aci) or (420 . rgb)) or a
    /// one-element list wrapping one. Returns the selected pair list.
    private static func acadTruecolordlg(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, host: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.range("acad_truecolordlg", args, min: 1, max: 3)
        let defaultACI = try truecolorDefaultACI(args[0])
        let allowByLayer = args.count < 2 || !args[1].isTrue
        guard let picked = await host.requestTrueColor(
            defaultACI: defaultACI, allowByLayer: allowByLayer)
        else {
            return .nilValue
        }
        return picked
    }

    /// Extracts an ACI default from (62 . n), ((62 . n)), (420 . rgb),
    /// a bare int, or a flat (62 n) two-list; rgb defaults map to nil
    /// (no ACI equivalent). Group codes written `62.` arrive as the
    /// real 62.0, so integral reals coerce.
    private static func truecolorDefaultACI(_ value: LispValue) throws -> Int? {
        switch value {
        case let .int(number):
            return number
        case let .real(number) where number == number.rounded():
            return Int(number)
        case let .cons(code, cdr):
            if let codeNumber = groupCode(code) {
                if codeNumber == 62, let number = aciValue(cdr) { return number }
                if codeNumber == 420 { return nil }
            }
            if let items = value.properList {
                if items.count == 1 {
                    return try truecolorDefaultACI(items[0])
                }
                if items.count == 2, let codeNumber = groupCode(items[0]) {
                    if codeNumber == 62 { return aciValue(items[1]) }
                    if codeNumber == 420 { return nil }
                }
            }
            throw LispError.typeMismatch(
                name: "acad_truecolordlg", expected: "color pair", got: value)
        default:
            throw LispError.typeMismatch(
                name: "acad_truecolordlg", expected: "color pair", got: value)
        }
    }

    private static func groupCode(_ value: LispValue) -> Int? {
        switch value {
        case let .int(number):
            return number
        case let .real(number) where number == number.rounded():
            return Int(number)
        default:
            return nil
        }
    }

    private static func aciValue(_ value: LispValue) -> Int? {
        groupCode(value)
    }

    /// (acad_truecolorcli color) prompts on the command line: an ACI
    /// integer 0-256, or R,G,B triple. Empty input keeps the default;
    /// Esc cancels. Returns ((62 . aci)) or ((420 . rgb)).
    private static func acadTruecolorcli(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, host: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly("acad_truecolorcli", args, 1)
        let defaultACI = try truecolorDefaultACI(args[0])
        while true {
            let answer = try await host.requestLine(
                prompt: "Enter color (ACI 0-256 or R,G,B): ")
            guard let answer else {
                // Bare Enter keeps the default.
                return defaultTruecolorList(defaultACI)
            }
            let trimmed = answer.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                return defaultTruecolorList(defaultACI)
            }
            if let parsed = parseTruecolor(trimmed) {
                return parsed
            }
            await host.write("Invalid color; enter ACI 0-256 or R,G,B.\n")
        }
    }

    private static func defaultTruecolorList(_ defaultACI: Int?) -> LispValue {
        LispValue(list: [
            LispValue.cons(head: .int(62), tail: .int(defaultACI ?? 7)),
        ])
    }

    private static func parseTruecolor(_ text: String) -> LispValue? {
        if let number = Int(text), (0...256).contains(number) {
            return LispValue(list: [LispValue.cons(head: .int(62), tail: .int(number))])
        }
        let parts = text.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        guard parts.count == 3,
              let red = Int(parts[0]), let green = Int(parts[1]),
              let blue = Int(parts[2]),
              (0...255).contains(red), (0...255).contains(green),
              (0...255).contains(blue)
        else {
            return nil
        }
        let packed = red * 65536 + green * 256 + blue
        return LispValue(list: [LispValue.cons(head: .int(420), tail: .int(packed))])
    }
}
