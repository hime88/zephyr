// ConvertBuiltins: unit-aware number <-> string conversions.
//
// rtos/angtos honor LUNITS/LUPREC/AUNITS/AUPREC/ANGBASE/ANGDIR through the
// host (sane AutoCAD defaults when the host has no value); angtof/distof
// parse the same formats back. Engineering/architectural forms assume the
// value is in inches, matching AutoCAD's imperial display.
import Foundation

enum ConvertBuiltins {
    static let table: [String: LispBuiltin] = [
        "RTOS": rtos,
        "ANGTOS": angtos,
        "ANGTOF": angtof,
        "DISTOF": distof,
    ]

    // MARK: - Host unit variables (AutoCAD defaults)

    static func intVar(_ host: any LispHost, _ name: String, default defaultValue: Int) async -> Int {
        guard let value = await host.getSystemVar(name) else { return defaultValue }
        if case let .int(v) = value { return v }
        if case let .real(v) = value { return Int(v) }
        return defaultValue
    }

    static func realVar(_ host: any LispHost, _ name: String, default defaultValue: Double) async -> Double {
        guard let value = await host.getSystemVar(name) else { return defaultValue }
        return value.asDouble ?? defaultValue
    }

    // MARK: - rtos

    private static func rtos(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, host: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.range("rtos", args, min: 1, max: 3)
        let value = try BuiltinArgs.number("rtos", args[0])
        var mode = await intVar(host, "LUNITS", default: 2)
        var precision = await intVar(host, "LUPREC", default: 4)
        if args.count >= 2 { mode = try BuiltinArgs.int("rtos", args[1]) }
        if args.count == 3 { precision = try BuiltinArgs.int("rtos", args[2]) }
        precision = max(0, min(8, precision))
        switch mode {
        case 1: return .string(formatScientific(value, precision: precision))
        case 2: return .string(formatDecimal(value, precision: precision))
        case 3: return .string(formatEngineering(value, precision: precision))
        case 4: return .string(formatArchitectural(value, precision: precision))
        case 5: return .string(formatFractional(value, precision: precision))
        default:
            throw LispError.typeMismatch(name: "rtos", expected: "mode 1-5", got: args[1])
        }
    }

    static func formatDecimal(_ value: Double, precision: Int) -> String {
        String(format: "%.\(precision)f", value)
    }

    static func formatScientific(_ value: Double, precision: Int) -> String {
        // AutoCAD style: 1.235E+02 (two-digit signed exponent).
        let raw = String(format: "%.\(precision)E", value)
        guard let eIndex = raw.firstIndex(of: "E") else { return raw }
        let mantissa = raw[..<eIndex]
        var exponent = String(raw[raw.index(after: eIndex)...])
        let sign = exponent.hasPrefix("-") ? "-" : "+"
        exponent = exponent.trimmingCharacters(in: CharacterSet(charactersIn: "+-"))
        while exponent.count < 2 { exponent = "0" + exponent }
        return "\(mantissa)E\(sign)\(exponent)"
    }

    /// Feet and decimal inches: 42.5 -> 3'-6.5000" (precision = decimals).
    static func formatEngineering(_ value: Double, precision: Int) -> String {
        let sign = value < 0 ? "-" : ""
        let inches = abs(value)
        let feet = Int(inches / 12)
        let remainder = inches - Double(feet * 12)
        return "\(sign)\(feet)'-\(formatDecimal(remainder, precision: precision))\""
    }

    /// Feet and fractional inches: 42.5 -> 3'-6 1/2" (precision = 1/2^n denom).
    static func formatArchitectural(_ value: Double, precision: Int) -> String {
        let sign = value < 0 ? "-" : ""
        let inches = abs(value)
        let feet = Int(inches / 12)
        let fraction = formatInchFraction(inches - Double(feet * 12), precision: precision)
        if fraction.whole == 0, fraction.numerator == 0 { return "\(sign)\(feet)'-0\"" }
        if fraction.numerator == 0 { return "\(sign)\(feet)'-\(fraction.whole)\"" }
        if fraction.whole == 0 {
            return "\(sign)\(feet)'-\(fraction.numerator)/\(fraction.denominator)\""
        }
        return "\(sign)\(feet)'-\(fraction.whole) \(fraction.numerator)/\(fraction.denominator)\""
    }

    /// Fractional inches: 42.5 -> 42 1/2.
    static func formatFractional(_ value: Double, precision: Int) -> String {
        let sign = value < 0 ? "-" : ""
        let fraction = formatInchFraction(abs(value), precision: precision)
        if fraction.numerator == 0 { return "\(sign)\(fraction.whole)" }
        if fraction.whole == 0 { return "\(sign)\(fraction.numerator)/\(fraction.denominator)" }
        return "\(sign)\(fraction.whole) \(fraction.numerator)/\(fraction.denominator)"
    }

    static func formatInchFraction(
        _ inches: Double, precision: Int
    ) -> (whole: Int, numerator: Int, denominator: Int) {
        let denominator = 1 << max(0, min(8, precision))
        let scaled = Int((inches * Double(denominator)).rounded())
        let whole = scaled / denominator
        let numerator = scaled % denominator
        if numerator == 0 { return (whole, 0, denominator) }
        let divisor = gcd(numerator, denominator)
        return (whole, numerator / divisor, denominator / divisor)
    }

    private static func gcd(_ a: Int, _ b: Int) -> Int {
        var a = abs(a)
        var b = abs(b)
        while b != 0 { (a, b) = (b, a % b) }
        return a
    }

    // MARK: - angtos

    private static func angtos(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, host: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.range("angtos", args, min: 1, max: 3)
        let angle = try BuiltinArgs.number("angtos", args[0])
        var mode = await intVar(host, "AUNITS", default: 0)
        var precision = await intVar(host, "AUPREC", default: 0)
        if args.count >= 2 { mode = try BuiltinArgs.int("angtos", args[1]) }
        if args.count == 3 { precision = try BuiltinArgs.int("angtos", args[2]) }
        precision = max(0, min(8, precision))
        let base = await realVar(host, "ANGBASE", default: 0)
        let clockwise = await intVar(host, "ANGDIR", default: 0) == 1
        var adjusted = clockwise ? base - angle : angle - base
        adjusted.formTruncatingRemainder(dividingBy: 2 * Double.pi)
        if adjusted < 0 { adjusted += 2 * Double.pi }
        switch mode {
        case 0:
            return .string(formatDecimal(adjusted * 180 / Double.pi, precision: precision))
        case 1:
            return .string(formatDegreesMinutesSeconds(adjusted, precision: precision))
        case 2:
            return .string(formatDecimal(adjusted * 200 / Double.pi, precision: precision) + "g")
        case 3:
            return .string(formatDecimal(adjusted, precision: precision) + "r")
        case 4:
            return .string(formatSurveyor(adjusted, precision: precision))
        default:
            throw LispError.typeMismatch(name: "angtos", expected: "mode 0-4", got: args[1])
        }
    }

    static func formatDegreesMinutesSeconds(_ radians: Double, precision: Int) -> String {
        // Round to precision decimals on the seconds field.
        let scale = pow(10.0, Double(precision))
        var totalSeconds = (radians * 180 / Double.pi * 3600 * scale).rounded() / scale
        var degrees = Int(totalSeconds / 3600)
        var remainder = totalSeconds - Double(degrees * 3600)
        var minutes = Int(remainder / 60)
        remainder -= Double(minutes * 60)
        var seconds = remainder
        // Carry overflow from rounding.
        if seconds >= 60 - 1e-9, precision == 0 {
            seconds = 0
            minutes += 1
        }
        if minutes >= 60 {
            minutes -= 60
            degrees += 1
        }
        if precision == 0 {
            return "\(degrees)d\(minutes)'\(Int(seconds.rounded()))\""
        }
        return "\(degrees)d\(minutes)'\(formatDecimal(seconds, precision: precision))\""
    }

    static func formatSurveyor(_ radians: Double, precision: Int) -> String {
        let degrees = radians * 180 / Double.pi
        let quadrant: String
        let bearing: Double
        switch degrees {
        case 0..<90: quadrant = "N % E"; bearing = degrees
        case 90..<180: quadrant = "S % E"; bearing = 180 - degrees
        case 180..<270: quadrant = "S % W"; bearing = degrees - 180
        default: quadrant = "N % W"; bearing = 360 - degrees
        }
        let dms = formatDegreesMinutesSeconds(bearing * Double.pi / 180, precision: precision)
        return quadrant.replacingOccurrences(of: "%", with: dms)
    }

    // MARK: - angtof

    private static func angtof(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, host: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.range("angtof", args, min: 1, max: 2)
        let text = try BuiltinArgs.string("angtof", args[0])
        var mode = await intVar(host, "AUNITS", default: 0)
        if args.count == 2 { mode = try BuiltinArgs.int("angtof", args[1]) }
        guard let radians = parseAngle(text, mode: mode) else { return .nilValue }
        // Inverse of the angtos base/direction adjustment.
        let base = await realVar(host, "ANGBASE", default: 0)
        let clockwise = await intVar(host, "ANGDIR", default: 0) == 1
        var angle = clockwise ? base - radians : radians + base
        angle.formTruncatingRemainder(dividingBy: 2 * Double.pi)
        if angle < 0 { angle += 2 * Double.pi }
        return .real(angle)
    }

    static func parseAngle(_ text: String, mode: Int) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        switch mode {
        case 0:
            return Double(trimmed).map { $0 * Double.pi / 180 }
        case 1:
            return parseDegreesMinutesSeconds(trimmed).map { $0 * Double.pi / 180 }
        case 2:
            let bare = trimmed.hasSuffix("g") ? String(trimmed.dropLast()) : trimmed
            return Double(bare.trimmingCharacters(in: .whitespaces)).map { $0 * Double.pi / 200 }
        case 3:
            let bare = trimmed.hasSuffix("r") ? String(trimmed.dropLast()) : trimmed
            return Double(bare.trimmingCharacters(in: .whitespaces))
        case 4:
            return parseSurveyor(trimmed)
        default:
            return Double(trimmed).map { $0 * Double.pi / 180 }
        }
    }

    /// Parses 45d30'15" (d, ', " separators, all parts optional but ordered).
    static func parseDegreesMinutesSeconds(_ text: String) -> Double? {
        var rest = text.trimmingCharacters(in: .whitespaces)
        var sign = 1.0
        if rest.hasPrefix("-") {
            sign = -1.0
            rest = String(rest.dropFirst())
        } else if rest.hasPrefix("+") {
            rest = String(rest.dropFirst())
        }
        var degrees = 0.0
        var minutes = 0.0
        var seconds = 0.0
        // Split on d, ', ".
        var number = ""
        var stage = 0 // 0=deg, 1=min, 2=sec
        var consumedSeparator = false
        for ch in rest {
            if ch.isWholeNumber || ch == "." {
                number.append(ch)
            } else if ch == "d" || ch == "D" {
                guard stage == 0, let v = Double(number) else { return nil }
                degrees = v
                number = ""
                stage = 1
                consumedSeparator = true
            } else if ch == "'" {
                guard stage <= 1, !number.isEmpty, let v = Double(number) else { return nil }
                if stage == 0 { degrees = v } else { minutes = v }
                number = ""
                stage = 2
                consumedSeparator = true
            } else if ch == "\"" {
                guard !number.isEmpty, let v = Double(number) else { return nil }
                if stage == 0 { degrees = v } else if stage == 1 { minutes = v } else { seconds = v }
                number = ""
                stage = 3
                consumedSeparator = true
            } else if ch.isWhitespace {
                continue
            } else {
                return nil
            }
        }
        if !number.isEmpty {
            guard let v = Double(number) else { return nil }
            if !consumedSeparator { degrees = v }
            else if stage == 1 { minutes = v }
            else if stage == 2 { seconds = v }
            else if stage == 0 { degrees = v }
            else { return nil }
        } else if !consumedSeparator {
            return nil
        }
        return sign * (degrees + minutes / 60 + seconds / 3600)
    }

    /// Parses surveyor bearings: N 45d30'0" E (also S..E, S..W, N..W).
    static func parseSurveyor(_ text: String) -> Double? {
        let parts = text.split(separator: " ").map(String.init)
        guard parts.count == 3 else { return nil }
        let (ns, rest, ew) = (parts[0].uppercased(), parts[1], parts[2].uppercased())
        guard (ns == "N" || ns == "S"), (ew == "E" || ew == "W") else { return nil }
        guard let bearing = parseDegreesMinutesSeconds(rest) else { return nil }
        let degrees: Double = {
            switch (ns, ew) {
            case ("N", "E"): return bearing
            case ("S", "E"): return 180 - bearing
            case ("S", "W"): return 180 + bearing
            default: return 360 - bearing
            }
        }()
        return degrees * Double.pi / 180
    }

    // MARK: - distof

    private static func distof(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.range("distof", args, min: 1, max: 2)
        let text = try BuiltinArgs.string("distof", args[0]).trimmingCharacters(in: .whitespaces)
        // Mode selects the preferred form but every parser is tried: distof
        // is forgiving and returns nil only when nothing parses.
        if let value = parseArchitecturalLength(text) { return .real(value) }
        if let value = parseFractionalLength(text) { return .real(value) }
        if let value = Double(text) { return .real(value) }
        return .nilValue
    }

    /// Parses 3'-6 1/2" (feet, inches, optional fraction, optional quote).
    static func parseArchitecturalLength(_ text: String) -> Double? {
        guard let dash = text.firstIndex(of: "-") else { return nil }
        let feetText = text[..<dash].trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "'"))
        guard let feet = Double(feetText) else { return nil }
        var rest = text[text.index(after: dash)...].trimmingCharacters(in: .whitespaces)
        if rest.hasSuffix("\"") { rest = String(rest.dropLast()) }
        let inches = parseFractionalLength(String(rest)) ?? 0
        return feet * 12 + inches
    }

    /// Parses 42 1/2, 6 1/2, 3/4, and plain decimals.
    static func parseFractionalLength(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.contains(" ") {
            let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count == 2, let whole = Double(parts[0]) else { return nil }
            guard let frac = parseSimpleFraction(String(parts[1])) else { return nil }
            return whole + (whole < 0 ? -frac : frac)
        }
        if let frac = parseSimpleFraction(trimmed) { return frac }
        return Double(trimmed)
    }

    static func parseSimpleFraction(_ text: String) -> Double? {
        guard text.contains("/") else { return nil }
        let parts = text.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2, let num = Double(parts[0]), let den = Double(parts[1]), den != 0 else {
            return nil
        }
        return num / den
    }
}
