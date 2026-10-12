// LispValue: the AutoLISP value domain.
//
// Lists are cons chains (not arrays) so dotted pairs from entget-style data
// ((0 . "LINE")) keep exact car/cdr semantics. Proper lists are chains that
// terminate in .nilValue; the `properList` helpers convert at builtin
// boundaries. All cases are value types: LispValue is Sendable and Equatable.
//
// Deliberate deviations from AutoCAD, kept minimal and documented:
// - Integers are 64-bit host ints, but arithmetic wraps at 32 bits to match
//   AutoLISP's 32-bit integer domain (see wrap32).
// - Symbol names are stored UPPERCASED (AutoLISP is case-insensitive).
// - Real display uses Swift's shortest-round-trip formatting.
import Foundation

/// One AutoLISP value.
public indirect enum LispValue: Sendable, Equatable {
    case nilValue
    case int(Int)
    case real(Double)
    case string(String)
    /// Always stored uppercased (the reader normalizes).
    case symbol(String)
    case cons(head: LispValue, tail: LispValue)
    /// Opaque entity handle (as produced by the host, e.g. "2A3F").
    case entityName(String)
    /// Opaque host-owned selection-set id.
    case selectionSet(Int)
    /// A caught vl-catch-all error object (never equal to anything).
    case errorObject(String)
    /// ActiveX-style wrapper (vlax-ename->vla-object). Carries the entity
    /// handle; only vla-getboundingbox is implemented in step 3 (the
    /// corpus's entire ActiveX surface). Full vla-*/vlax-* is Tier 2.
    case vlaObject(String)
}

// MARK: - Constructors

extension LispValue {
    /// The true value.
    public static var t: LispValue { .symbol("T") }

    /// Builds a proper (nil-terminated) list.
    public init(list items: [LispValue]) {
        var out: LispValue = .nilValue
        for item in items.reversed() { out = .cons(head: item, tail: out) }
        self = out
    }

    /// Builds a proper list of strings (convenience for string lists).
    public init(stringList items: [String]) {
        self.init(list: items.map(LispValue.string))
    }

    /// Wraps Int32 arithmetic: AutoLISP integers are 32-bit.
    public static func wrap32(_ value: Int) -> Int {
        Int(Int32(truncatingIfNeeded: value))
    }
}

// MARK: - Predicates and decomposition

extension LispValue {
    /// AutoLISP truth: ONLY nil is false. 0, "", and T are all true.
    public var isTrue: Bool {
        if case .nilValue = self { return false }
        return true
    }

    public var isNil: Bool {
        if case .nilValue = self { return true }
        return false
    }

    public var isAtom: Bool {
        if case .cons = self { return false }
        return true
    }

    public var isProperList: Bool {
        var cursor = self
        while true {
            switch cursor {
            case .nilValue: return true
            case let .cons(_, tail): cursor = tail
            default: return false
            }
        }
    }

    /// Proper-list elements, or nil for improper lists and non-lists
    /// (nil itself yields the empty array).
    public var properList: [LispValue]? {
        var out: [LispValue] = []
        var cursor = self
        while true {
            switch cursor {
            case .nilValue: return out
            case let .cons(head, tail): out.append(head); cursor = tail
            default: return nil
            }
        }
    }

    /// Numeric value as Double, or nil for non-numbers.
    public var asDouble: Double? {
        switch self {
        case let .int(v): return Double(v)
        case let .real(v): return v
        default: return nil
        }
    }

    /// Point coordinates for 2D/3D numeric lists, or nil otherwise.
    public var asPoint: [Double]? {
        guard let items = properList, items.count == 2 || items.count == 3 else { return nil }
        var coords: [Double] = []
        for item in items {
            guard let v = item.asDouble else { return nil }
            coords.append(v)
        }
        return coords
    }
}

// MARK: - Display (princ / prin1 / print)

extension LispValue {
    /// princ form: strings/symbols bare, nil as the empty string.
    public var displayString: String {
        switch self {
        case .nilValue: return ""
        case let .int(v): return String(v)
        case let .real(v): return LispValue.formatReal(v)
        case let .string(v): return v
        case let .symbol(v): return v
        case .cons: return prin1String
        case let .entityName(h): return "<Entity name: \(h)>"
        case let .selectionSet(id): return "<Selection set: \(id)>"
        case let .errorObject(msg): return "#<vl-catch-all-error \"\(msg)\">"
        case let .vlaObject(h): return "#<VLA-OBJECT \(h)>"
        }
    }

    /// prin1 form: strings quoted, nil as "nil", dotted tails dotted.
    public var prin1String: String {
        switch self {
        case .nilValue: return "nil"
        case let .int(v): return String(v)
        case let .real(v): return LispValue.formatReal(v)
        case let .string(v): return "\"\(LispValue.escape(v))\""
        case let .symbol(v): return v
        case .cons: return printList(self)
        case let .entityName(h): return "<Entity name: \(h)>"
        case let .selectionSet(id): return "<Selection set: \(id)>"
        case let .errorObject(msg): return "#<vl-catch-all-error \"\(LispValue.escape(msg))\">"
        case let .vlaObject(h): return "#<VLA-OBJECT \(h)>"
        }
    }

    /// Shortest round-trip real formatting.
    public static func formatReal(_ value: Double) -> String {
        if value.truncatingRemainder(dividingBy: 1) == 0, abs(value) < 1e15 {
            return "\(Int64(value)).0"
        }
        return String(value)
    }

    static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}

private func printList(_ value: LispValue) -> String {
    var parts: [String] = []
    var cursor = value
    while true {
        switch cursor {
        case .nilValue:
            return "(" + parts.joined(separator: " ") + ")"
        case let .cons(head, tail):
            parts.append(head.prin1String)
            cursor = tail
        default:
            // Improper tail: dotted notation.
            return "(" + parts.joined(separator: " ") + " . " + cursor.prin1String + ")"
        }
    }
}
