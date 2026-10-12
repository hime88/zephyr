// LispInputParsing: text parsers shared by input builtins and hosts.
//
// One implementation serves the CLI host, scripted test hosts, and the
// MainActor CAD host: point text ("1,2" / "1,2,3"), strict numbers, and
// unit-aware angle text.

/// Shared text parsers for user input. All functions are pure and Sendable.
public enum LispInputParsing {
    /// Parses "x,y" or "x,y,z" (whitespace tolerated, <>r alternate form
    /// rejected). Returns nil unless the whole string is coordinates.
    public static func parsePointText(_ text: String) -> [Double]? {
        let parts = text.split(separator: ",", omittingEmptySubsequences: false).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        guard parts.count == 2 || parts.count == 3 else { return nil }
        var coords: [Double] = []
        for part in parts {
            guard !part.isEmpty, let value = Double(part) else { return nil }
            coords.append(value)
        }
        return coords
    }

    /// Strict whole-string integer (optional sign, digits only).
    public static func parseInt(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        var body = trimmed
        if body.hasPrefix("+") || body.hasPrefix("-") { body = String(body.dropFirst()) }
        guard !body.isEmpty, body.allSatisfy(\.isWholeNumber) else { return nil }
        guard let value = Int(trimmed) else { return nil }
        return LispValue.wrap32(value)
    }

    /// Strict whole-string real (delegates shape to Double after a scan).
    public static func parseReal(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        // Reject trailing garbage Double() would otherwise ignore... it does
        // not ignore any, but malformed exponents must fail loudly below.
        guard Double(trimmed) != nil else { return nil }
        // Double() accepts "nan"/"inf" spellings; AutoLISP input does not.
        let lower = trimmed.lowercased()
        if lower.contains("nan") || lower.contains("inf") { return nil }
        return Double(trimmed)
    }

    /// Angle text in an AUNITS mode: plain number (radians as typed when the
    /// mode is decimal degrees... no: bare numbers are degrees in mode 0),
    /// falling back to full angtof parsing otherwise.
    ///
    /// Rule: a bare Double parses per the mode (degrees in mode 0, grads in
    /// mode 2, radians in mode 3); anything else goes through the angtof
    /// grammar (d/m/s, surveyor). Returns radians or nil.
    public static func parseAngleText(_ text: String, mode: Int) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if let bare = Double(trimmed) {
            switch mode {
            case 2: return bare * Double.pi / 200
            case 3: return bare
            default: return bare * Double.pi / 180
            }
        }
        return ConvertBuiltins.parseAngle(trimmed, mode: mode)
    }
}
