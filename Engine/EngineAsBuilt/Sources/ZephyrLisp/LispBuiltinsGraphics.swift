// GraphicsBuiltins: Wave-C transient graphics + views + osnap —
// graphscr/textscr/grclear/grdraw/grtext/grvecs/redraw/setview/osnap.
// All display builtins return nil per the oracle; vectors route to
// the host transient surface (ignored until Tier 2 renders it).
import Foundation

enum GraphicsBuiltins {
    static let table: [String: LispBuiltin] = [
        "GRAPHSCR": graphscr,
        "TEXTSCR": textscr,
        "GRCLEAR": grclear,
        "GRDRAW": grdraw,
        "GRTEXT": grtext,
        "GRVECS": grvecs,
        "REDRAW": redraw,
        "SETVIEW": setview,
        "OSNAP": osnap,
    ]

    /// Single-window host: both display switches are accepted no-ops.
    private static func graphscr(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly("graphscr", args, 0)
        return .nilValue
    }

    private static func textscr(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly("textscr", args, 0)
        return .nilValue
    }

    private static func grclear(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, host: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly("grclear", args, 0)
        await host.grClear()
        return .nilValue
    }

    private static func grdraw(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, host: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.range("grdraw", args, min: 3, max: 4)
        let from = try BuiltinArgs.point("grdraw", args[0])
        let to = try BuiltinArgs.point("grdraw", args[1])
        let color = try BuiltinArgs.int("grdraw", args[2])
        let highlight = args.count == 4 && args[3].isTrue
        await host.grDraw(from: from, to: to, color: color, highlight: highlight)
        return .nilValue
    }

    /// (grtext [box text [highlight]]). No arguments clears the status
    /// line (box -1, empty text).
    private static func grtext(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, host: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.range("grtext", args, min: 0, max: 3)
        if args.isEmpty {
            await host.grText(box: -1, text: "", highlight: false)
            return .nilValue
        }
        guard args.count >= 2 else {
            throw LispError.arity(
                name: "grtext", expected: "() or (box text [highlight])", got: args.count)
        }
        let box = try BuiltinArgs.int("grtext", args[0])
        let text = try BuiltinArgs.string("grtext", args[1])
        let highlight = args.count == 3 && args[2].isTrue
        await host.grText(box: box, text: text, highlight: highlight)
        return .nilValue
    }

    /// (grvecs (color pt pt color pt pt ...) [trans]). The vector list
    /// alternates color indices and point pairs; trans is a 4x4
    /// row-major matrix the host applies.
    private static func grvecs(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, host: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.range("grvecs", args, min: 1, max: 2)
        let items = try BuiltinArgs.properList("grvecs", args[0])
        var vectors: [(color: Int, from: [Double], to: [Double])] = []
        var index = 0
        var color = 7
        while index < items.count {
            // A bare integer is a color (points are always lists); a
            // trailing color with no pair is ignored.
            if case let .int(candidate) = items[index] {
                color = candidate
                index += 1
                continue
            }
            guard index + 1 < items.count else {
                throw LispError.typeMismatch(
                    name: "grvecs", expected: "point pair", got: items[index])
            }
            let from = try BuiltinArgs.point("grvecs", items[index])
            let to = try BuiltinArgs.point("grvecs", items[index + 1])
            vectors.append((color: color, from: from, to: to))
            index += 2
        }
        var transform: [[Double]]?
        if args.count == 2 {
            let rows = try BuiltinArgs.properList("grvecs", args[1])
            guard rows.count == 4 else {
                throw LispError.typeMismatch(
                    name: "grvecs", expected: "4x4 matrix", got: args[1])
            }
            transform = try rows.map { row in
                let cells = try BuiltinArgs.properList("grvecs", row)
                guard cells.count == 4 else {
                    throw LispError.typeMismatch(
                        name: "grvecs", expected: "4x4 matrix", got: args[1])
                }
                return try cells.map { try BuiltinArgs.number("grvecs", $0) }
            }
        }
        await host.grVecs(vectors, transform: transform)
        return .nilValue
    }

    /// (redraw [ename [mode]]), modes 1-4. Unknown mode is an error;
    /// entity names must be well-formed but need not exist (the host
    /// ignores missing handles, like AutoCAD off-screen entities).
    private static func redraw(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, host: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.range("redraw", args, min: 0, max: 2)
        var handle: String?
        var mode = 1
        if !args.isEmpty {
            guard case let .entityName(name) = args[0] else {
                throw LispError.typeMismatch(
                    name: "redraw", expected: "entity name", got: args[0])
            }
            handle = name
        }
        if args.count == 2 {
            mode = try BuiltinArgs.int("redraw", args[1])
            guard (1...4).contains(mode) else {
                throw LispError.hostError("redraw: mode must be 1-4")
            }
        }
        await host.redraw(handle: handle, mode: mode)
        return .nilValue
    }

    private static func setview(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, host: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.range("setview", args, min: 1, max: 2)
        let name = try BuiltinArgs.string("setview", args[0])
        var viewport: Int?
        if args.count == 2, !args[1].isNil {
            viewport = try BuiltinArgs.int("setview", args[1])
        }
        return await host.setView(name: name, viewport: viewport) ? .t : .nilValue
    }

    /// (osnap pt "_end,_mid") snaps through the host. Modes are comma-
    /// separated with optional underscore prefixes; _non returns the
    /// point unchanged; unsupported modes (INT/PER/TAN/...) match
    /// nothing. Returns a 3D point or nil.
    private static func osnap(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, host: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly("osnap", args, 2)
        var point = try BuiltinArgs.point("osnap", args[0])
        let rawModes = try BuiltinArgs.string("osnap", args[1])
        let modes = rawModes.split(separator: ",").map { part in
            part.trimmingCharacters(in: .whitespaces).uppercased()
                .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        }
        if modes.contains("NON") {
            while point.count < 3 { point.append(0) }
            return LispValue(list: point.map(LispValue.real))
        }
        let canonical = modes.compactMap { canonicalMode($0) }
        guard !canonical.isEmpty else { return .nilValue }
        guard let snapped = await host.osnap(point: point, modes: canonical) else {
            return .nilValue
        }
        return LispValue(list: snapped.map(LispValue.real))
    }

    /// Canonical mode names the host understands. Prefix matching
    /// follows AutoCAD abbreviations (END, MID, CEN, QUA, INS, NEA).
    private static func canonicalMode(_ mode: String) -> String? {
        for candidate in ["END", "MID", "CEN", "QUA", "INS", "NEA"] {
            if candidate.hasPrefix(mode), !mode.isEmpty {
                return candidate
            }
        }
        switch mode {
        case "ENDPOINT": return "END"
        case "MIDPOINT": return "MID"
        case "CENTER": return "CEN"
        case "QUADRANT": return "QUA"
        case "INSERT", "INSERTION": return "INS"
        case "NEAREST": return "NEA"
        default: return nil
        }
    }
}
