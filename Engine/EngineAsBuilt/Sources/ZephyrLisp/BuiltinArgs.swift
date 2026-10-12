// BuiltinArgs: shared arity/type guards for builtins.

enum BuiltinArgs {
    static func exactly(_ name: String, _ args: [LispValue], _ count: Int) throws {
        guard args.count == count else {
            throw LispError.arity(name: name, expected: "\(count)", got: args.count)
        }
    }

    static func range(_ name: String, _ args: [LispValue], min: Int, max: Int? = nil) throws {
        guard args.count >= min, max.map({ args.count <= $0 }) ?? true else {
            let expected = max.map { "\(min) to \($0)" } ?? "\(min) or more"
            throw LispError.arity(name: name, expected: expected, got: args.count)
        }
    }

    static func number(_ name: String, _ value: LispValue) throws -> Double {
        guard let v = value.asDouble else {
            throw LispError.typeMismatch(name: name, expected: "number", got: value)
        }
        return v
    }

    static func int(_ name: String, _ value: LispValue) throws -> Int {
        guard case let .int(v) = value else {
            throw LispError.typeMismatch(name: name, expected: "integer", got: value)
        }
        return v
    }

    static func string(_ name: String, _ value: LispValue) throws -> String {
        guard case let .string(v) = value else {
            throw LispError.typeMismatch(name: name, expected: "string", got: value)
        }
        return v
    }

    static func symbol(_ name: String, _ value: LispValue) throws -> String {
        guard case let .symbol(v) = value else {
            throw LispError.typeMismatch(name: name, expected: "symbol", got: value)
        }
        return v
    }

    static func properList(_ name: String, _ value: LispValue) throws -> [LispValue] {
        guard let items = value.properList else {
            throw LispError.typeMismatch(name: name, expected: "proper list", got: value)
        }
        return items
    }

    static func point(_ name: String, _ value: LispValue) throws -> [Double] {
        guard let coords = value.asPoint else {
            throw LispError.typeMismatch(name: name, expected: "2D/3D point", got: value)
        }
        return coords
    }
}
