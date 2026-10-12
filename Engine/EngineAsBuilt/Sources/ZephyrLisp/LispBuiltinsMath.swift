// MathBuiltins: arithmetic, comparisons, trig, and point geometry.
//
// Integer domain is 32-bit wrapped (AutoLISP). All-int arithmetic stays int
// (including truncating integer division); any real promotes to real.
import Foundation

enum MathBuiltins {
    static let table: [String: LispBuiltin] = [
        "+": arithmetic("+", { $0 + $1 }, intCombine: +),
        "-": subtract,
        "*": arithmetic("*", { $0 * $1 }, intCombine: *),
        "/": divide,
        "=": compare("=") { $0 == $1 },
        "/=": compare("/=") { $0 != $1 },
        "<": compare("<") { $0 < $1 },
        "<=": compare("<=") { $0 <= $1 },
        ">": compare(">") { $0 > $1 },
        ">=": compare(">=") { $0 >= $1 },
        "1+": onePlus,
        "1-": oneMinus,
        "~": bitNot,
        "ABS": abs_,
        "ATAN": atan_,
        "COS": unaryReal("cos", Foundation.cos),
        "SIN": unaryReal("sin", Foundation.sin),
        "EXP": unaryReal("exp", Foundation.exp),
        "EXPT": expt,
        "FIX": fix,
        "FLOAT": float_,
        "GCD": gcd,
        "LOG": log_,
        "MAX": minmax("max", Swift.max),
        "MIN": minmax("min", Swift.min),
        "REM": rem,
        "SQRT": sqrt_,
        "MINUSP": minusp,
        "ZEROP": zerop,
        "NUMBERP": numberp,
        "BOOLE": boole,
        "LOGAND": logand,
        "LOGIOR": logior,
        "LSH": lsh,
        "ANGLE": angle,
        "DISTANCE": distance,
        "POLAR": polar,
        "INTERS": inters,
        "CVUNIT": cvunit,
    ]

    // MARK: - Variadic arithmetic (+ * and/or comparisons)

    private static func arithmetic(
        _ name: String, _ combine: @Sendable @escaping (Double, Double) -> Double,
        intCombine: (@Sendable (Int, Int) -> Int)? = nil
    ) -> LispBuiltin {
        { _, args, _, _ in
            if args.allSatisfy({ if case .int = $0 { return true } else { return false } }),
                let intCombine
            {
                var acc = name == "*" ? 1 : 0
                for arg in args {
                    guard case let .int(v) = arg else { break }
                    acc = LispValue.wrap32(intCombine(acc, v))
                }
                return .int(acc)
            }
            guard !args.isEmpty else {
                // (+) -> 0, (*) -> 1 (additive/multiplicative identity).
                return .int(name == "*" ? 1 : 0)
            }
            var values: [Double] = []
            for arg in args { values.append(try BuiltinArgs.number(name, arg)) }
            return .real(values.dropFirst().reduce(values[0], combine))
        }
    }

    private static func subtract(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        if args.isEmpty { return .int(0) }
        if args.count == 1 {
            switch args[0] {
            case let .int(v): return .int(LispValue.wrap32(-v))
            case let .real(v): return .real(-v)
            default: throw LispError.typeMismatch(name: "-", expected: "number", got: args[0])
            }
        }
        if args.allSatisfy({ if case .int = $0 { return true } else { return false } }) {
            var acc: Int = {
                guard case let .int(v) = args[0] else { return 0 }
                return v
            }()
            for arg in args.dropFirst() {
                guard case let .int(v) = arg else { break }
                acc = LispValue.wrap32(acc - v)
            }
            return .int(acc)
        }
        var values: [Double] = []
        for arg in args { values.append(try BuiltinArgs.number("-", arg)) }
        return .real(values.dropFirst().reduce(values[0], -))
    }

    private static func divide(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        guard !args.isEmpty else {
            throw LispError.arity(name: "/", expected: "1 or more", got: 0)
        }
        if args.allSatisfy({ if case .int = $0 { return true } else { return false } }) {
            let ints = args.map { v -> Int in
                guard case let .int(n) = v else { return 0 }
                return n
            }
            if ints.count == 1 {
                // Reciprocal with integer truncation: (/ 2) -> 0.
                guard ints[0] != 0 else { throw LispError.divisionByZero }
                return .int(1 / ints[0])
            }
            var acc = ints[0]
            for v in ints.dropFirst() {
                guard v != 0 else { throw LispError.divisionByZero }
                acc = acc / v
            }
            return .int(acc)
        }
        var values: [Double] = []
        for arg in args { values.append(try BuiltinArgs.number("/", arg)) }
        if values.count == 1 {
            guard values[0] != 0 else { throw LispError.divisionByZero }
            return .real(1 / values[0])
        }
        var acc = values[0]
        for v in values.dropFirst() {
            guard v != 0 else { throw LispError.divisionByZero }
            acc = acc / v
        }
        return .real(acc)
    }

    // MARK: - Comparisons (all six compare strings lexicographically)

    private static func compare(
        _ name: String, _ predicate: @Sendable @escaping (Double, Double) -> Bool
    ) -> LispBuiltin {
        { _, args, _, _ in
            try BuiltinArgs.range(name, args, min: 1)
            if args.allSatisfy({ if case .string = $0 { return true } else { return false } }) {
                let strings: [String] = args.map {
                    guard case let .string(s) = $0 else { return "" }
                    return s
                }
                if name == "=" || name == "/=" {
                    let allEqual = strings.dropFirst().allSatisfy { $0 == strings[0] }
                    return .tOrNil(name == "=" ? allEqual : !allEqual)
                }
                for pair in zip(strings, strings.dropFirst()) {
                    let order: ComparisonResult = pair.0 == pair.1 ? .orderedSame
                        : pair.0 < pair.1 ? .orderedAscending : .orderedDescending
                    let holds: Bool = switch name {
                    case "<": order == .orderedAscending
                    case "<=": order != .orderedDescending
                    case ">": order == .orderedDescending
                    default: order != .orderedAscending // >=
                    }
                    if !holds { return .nilValue }
                }
                return .t
            }
            var values: [Double] = []
            for arg in args { values.append(try BuiltinArgs.number(name, arg)) }
            for pair in zip(values, values.dropFirst()) {
                if !predicate(pair.0, pair.1) { return .nilValue }
            }
            return .t
        }
    }

    // MARK: - Unary numerics

    private static func onePlus(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly("1+", args, 1)
        switch args[0] {
        case let .int(v): return .int(LispValue.wrap32(v + 1))
        case let .real(v): return .real(v + 1)
        default: throw LispError.typeMismatch(name: "1+", expected: "number", got: args[0])
        }
    }

    private static func oneMinus(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly("1-", args, 1)
        switch args[0] {
        case let .int(v): return .int(LispValue.wrap32(v - 1))
        case let .real(v): return .real(v - 1)
        default: throw LispError.typeMismatch(name: "1-", expected: "number", got: args[0])
        }
    }

    private static func bitNot(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly("~", args, 1)
        let v = try BuiltinArgs.int("~", args[0])
        return .int(LispValue.wrap32(~v))
    }

    private static func abs_(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly("abs", args, 1)
        switch args[0] {
        case let .int(v): return .int(v == Int(Int32.min) ? v : abs(v))
        case let .real(v): return .real(abs(v))
        default: throw LispError.typeMismatch(name: "abs", expected: "number", got: args[0])
        }
    }

    private static func unaryReal(
        _ name: String, _ fn: @Sendable @escaping (Double) -> Double
    ) -> LispBuiltin {
        { _, args, _, _ in
            try BuiltinArgs.exactly(name, args, 1)
            return .real(fn(try BuiltinArgs.number(name, args[0])))
        }
    }

    private static func atan_(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.range("atan", args, min: 1, max: 2)
        if args.count == 1 {
            return .real(Foundation.atan(try BuiltinArgs.number("atan", args[0])))
        }
        let y = try BuiltinArgs.number("atan", args[0])
        let x = try BuiltinArgs.number("atan", args[1])
        return .real(Foundation.atan2(y, x))
    }

    private static func expt(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly("expt", args, 2)
        if case let .int(base) = args[0], case let .int(power) = args[1], power >= 0 {
            var acc = 1
            for _ in 0..<power { acc = LispValue.wrap32(acc * base) }
            return .int(acc)
        }
        let base = try BuiltinArgs.number("expt", args[0])
        let power = try BuiltinArgs.number("expt", args[1])
        return .real(Foundation.pow(base, power))
    }

    private static func fix(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly("fix", args, 1)
        switch args[0] {
        case let .int(v): return .int(v)
        case let .real(v): return .int(LispValue.wrap32(Int(v)))
        default: throw LispError.typeMismatch(name: "fix", expected: "number", got: args[0])
        }
    }

    private static func float_(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly("float", args, 1)
        return .real(try BuiltinArgs.number("float", args[0]))
    }

    private static func gcd(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly("gcd", args, 2)
        var a = abs(Int(try BuiltinArgs.number("gcd", args[0])))
        var b = abs(Int(try BuiltinArgs.number("gcd", args[1])))
        while b != 0 { (a, b) = (b, a % b) }
        return .int(LispValue.wrap32(a))
    }

    private static func log_(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly("log", args, 1)
        let v = try BuiltinArgs.number("log", args[0])
        guard v > 0 else { throw LispError.hostError("log of non-positive number") }
        return .real(Foundation.log(v))
    }

    private static func minmax(
        _ name: String, _ pick: @Sendable @escaping (Double, Double) -> Double
    ) -> LispBuiltin {
        { _, args, _, _ in
            try BuiltinArgs.range(name, args, min: 1)
            if args.allSatisfy({ if case .int = $0 { return true } else { return false } }) {
                var best: Int = {
                    guard case let .int(v) = args[0] else { return 0 }
                    return v
                }()
                for arg in args.dropFirst() {
                    guard case let .int(v) = arg else { break }
                    best = Int(pick(Double(best), Double(v)))
                }
                return .int(best)
            }
            var values: [Double] = []
            for arg in args { values.append(try BuiltinArgs.number(name, arg)) }
            return .real(values.dropFirst().reduce(values[0], pick))
        }
    }

    private static func rem(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.range("rem", args, min: 2)
        if args.allSatisfy({ if case .int = $0 { return true } else { return false } }) {
            var acc: Int = {
                guard case let .int(v) = args[0] else { return 0 }
                return v
            }()
            for arg in args.dropFirst() {
                guard case let .int(v) = arg else { break }
                guard v != 0 else { throw LispError.divisionByZero }
                acc = acc % v
            }
            return .int(acc)
        }
        var values: [Double] = []
        for arg in args { values.append(try BuiltinArgs.number("rem", arg)) }
        var acc = values[0]
        for v in values.dropFirst() {
            guard v != 0 else { throw LispError.divisionByZero }
            acc = acc.truncatingRemainder(dividingBy: v)
        }
        return .real(acc)
    }

    private static func sqrt_(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly("sqrt", args, 1)
        let v = try BuiltinArgs.number("sqrt", args[0])
        guard v >= 0 else { throw LispError.hostError("sqrt of negative number") }
        return .real(Foundation.sqrt(v))
    }

    private static func minusp(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly("minusp", args, 1)
        guard let v = args[0].asDouble else { return .nilValue }
        return .tOrNil(v < 0)
    }

    private static func zerop(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly("zerop", args, 1)
        guard let v = args[0].asDouble else { return .nilValue }
        return .tOrNil(v == 0)
    }

    private static func numberp(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly("numberp", args, 1)
        return .tOrNil(args[0].asDouble != nil)
    }

    // MARK: - Bitwise (32-bit domain)

    /// All 16 Common Lisp boolean operations selected by op code 0-15.
    /// Row order (from CL, which AutoCAD follows): bit0 = f(1,1),
    /// bit1 = f(1,0), bit2 = f(0,1), bit3 = f(0,0). Hence AND = 1,
    /// XOR = 6, IOR = 7.
    private static func boole(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly("boole", args, 3)
        let op = try BuiltinArgs.int("boole", args[0])
        guard (0...15).contains(op) else {
            throw LispError.typeMismatch(name: "boole", expected: "operation 0-15", got: args[0])
        }
        let a = UInt32(truncatingIfNeeded: try BuiltinArgs.int("boole", args[1]))
        let b = UInt32(truncatingIfNeeded: try BuiltinArgs.int("boole", args[2]))
        var out: UInt32 = 0
        for bit in 0..<32 {
            let abit = (a >> bit) & 1
            let bbit = (b >> bit) & 1
            let row = (abit == 0 ? 2 : 0) | (bbit == 0 ? 1 : 0)
            if (op >> row) & 1 == 1 { out |= (1 << bit) }
        }
        return .int(Int(Int32(bitPattern: out)))
    }

    private static func logand(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.range("logand", args, min: 1)
        var acc = ~0
        for arg in args { acc &= try BuiltinArgs.int("logand", arg) }
        return .int(LispValue.wrap32(acc))
    }

    private static func logior(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.range("logior", args, min: 1)
        var acc = 0
        for arg in args { acc |= try BuiltinArgs.int("logior", arg) }
        return .int(LispValue.wrap32(acc))
    }

    private static func lsh(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly("lsh", args, 2)
        let value = Int32(truncatingIfNeeded: try BuiltinArgs.int("lsh", args[0]))
        let shift = try BuiltinArgs.int("lsh", args[1])
        if shift >= 0 {
            return .int(LispValue.wrap32(Int(value) << min(shift, 31)))
        }
        // Arithmetic (sign-extending) right shift.
        return .int(Int(value >> min(-shift, 31)))
    }

    // MARK: - Point geometry (2D/3D numeric lists)

    private static func angle(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly("angle", args, 2)
        let from = try BuiltinArgs.point("angle", args[0])
        let to = try BuiltinArgs.point("angle", args[1])
        var radians = Foundation.atan2(to[1] - from[1], to[0] - from[0])
        if radians < 0 { radians += 2 * Double.pi }
        return .real(radians)
    }

    private static func distance(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly("distance", args, 2)
        let a = try BuiltinArgs.point("distance", args[0])
        let b = try BuiltinArgs.point("distance", args[1])
        var sum = 0.0
        for index in 0..<max(a.count, b.count) {
            let da = index < a.count ? a[index] : 0
            let db = index < b.count ? b[index] : 0
            sum += (da - db) * (da - db)
        }
        return .real(Foundation.sqrt(sum))
    }

    private static func polar(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly("polar", args, 3)
        let base = try BuiltinArgs.point("polar", args[0])
        let radians = try BuiltinArgs.number("polar", args[1])
        let dist = try BuiltinArgs.number("polar", args[2])
        let x = base[0] + dist * Foundation.cos(radians)
        let y = base[1] + dist * Foundation.sin(radians)
        if base.count == 3 {
            return LispValue(list: [.real(x), .real(y), .real(base[2])])
        }
        return LispValue(list: [.real(x), .real(y)])
    }

    private static func inters(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.range("inters", args, min: 4, max: 5)
        let p1 = try BuiltinArgs.point("inters", args[0])
        let p2 = try BuiltinArgs.point("inters", args[1])
        let p3 = try BuiltinArgs.point("inters", args[2])
        let p4 = try BuiltinArgs.point("inters", args[3])
        let onSeg = args.count == 5 ? args[4].isTrue : false
        let d = (p2[0] - p1[0]) * (p4[1] - p3[1]) - (p2[1] - p1[1]) * (p4[0] - p3[0])
        guard d != 0 else { return .nilValue } // Parallel.
        let t = ((p3[0] - p1[0]) * (p4[1] - p3[1]) - (p3[1] - p1[1]) * (p4[0] - p3[0])) / d
        let u = ((p3[0] - p1[0]) * (p2[1] - p1[1]) - (p3[1] - p1[1]) * (p2[0] - p1[0])) / d
        if onSeg, t < 0 || t > 1 || u < 0 || u > 1 { return .nilValue }
        // AutoCAD inters always returns a 3D point: Z interpolates when
        // the inputs carry elevation, else 0.
        let z1 = p1.count > 2 ? p1[2] : 0
        let z2 = p2.count > 2 ? p2[2] : 0
        return LispValue(list: [
            .real(p1[0] + t * (p2[0] - p1[0])),
            .real(p1[1] + t * (p2[1] - p1[1])),
            .real(z1 + t * (z2 - z1)),
        ])
    }

    // MARK: - Unit conversion (linear factors to meters)

    private static let metersPerUnit: [String: Double] = [
        "inches": 0.0254, "inch": 0.0254, "in": 0.0254,
        "feet": 0.3048, "foot": 0.3048, "ft": 0.3048,
        "miles": 1609.344, "mile": 1609.344, "mi": 1609.344,
        "millimeters": 0.001, "millimeter": 0.001, "mm": 0.001,
        "centimeters": 0.01, "centimeter": 0.01, "cm": 0.01,
        "meters": 1.0, "meter": 1.0, "m": 1.0,
        "kilometers": 1000.0, "kilometer": 1000.0, "km": 1000.0,
        "microinches": 0.0254e-6, "microinch": 0.0254e-6,
        "mils": 0.0254e-3, "mil": 0.0254e-3,
        "yards": 0.9144, "yard": 0.9144, "yd": 0.9144,
        "angstroms": 1e-10, "nanometers": 1e-9, "microns": 1e-6,
        "decimeters": 0.1, "dekameters": 10.0, "hectometers": 100.0,
        "gigameters": 1e9, "astronomical": 1.495978707e11,
        "lightyears": 9.4607304725808e15, "parsecs": 3.08567758149137e16,
    ]

    private static func cvunit(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly("cvunit", args, 3)
        let value = try BuiltinArgs.number("cvunit", args[0])
        let from = try BuiltinArgs.string("cvunit", args[1]).lowercased()
        let to = try BuiltinArgs.string("cvunit", args[2]).lowercased()
        guard let fromFactor = metersPerUnit[from] else {
            throw LispError.hostError("unknown unit: \(from)")
        }
        guard let toFactor = metersPerUnit[to] else {
            throw LispError.hostError("unknown unit: \(to)")
        }
        return .real(value * fromFactor / toFactor)
    }
}

// MARK: - t-or-nil helper

extension LispValue {
    static func tOrNil(_ condition: Bool) -> LispValue {
        condition ? .t : .nilValue
    }
}
