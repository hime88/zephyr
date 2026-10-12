// ListBuiltins: cons-cell operations over proper and dotted lists.
//
// car/cdr are nil-forgiving ((car nil) -> nil); structural builtins
// (length, reverse, nth) require proper lists. Higher-order helpers
// (vl-sort, vl-every, ...) apply AutoLISP predicates through the evaluator.

enum ListBuiltins {
    static let table: [String: LispBuiltin] = [
        "CONS": cons,
        "LIST": list,
        "CAR": car,
        "CDR": cdr,
        "CADR": cadr(depth: 1, name: "cadr"),
        "CADDR": cadr(depth: 2, name: "caddr"),
        "LAST": last,
        "LENGTH": length,
        "NTH": nth,
        "APPEND": append,
        "REVERSE": reverse,
        "MEMBER": member,
        "ASSOC": assoc,
        "SUBST": subst,
        "VL-LIST*": vlListStar,
        "VL-LIST-LENGTH": vlListLength,
        "VL-LIST->STRING": vlListToString,
        "VL-CONSP": vlConsp,
        "VL-EVERY": vlEvery,
        "VL-SOME": vlSome,
        "VL-MEMBER-IF": vlMemberIf,
        "VL-MEMBER-IF-NOT": vlMemberIfNot,
        "VL-POSITION": vlPosition,
        "VL-REMOVE": vlRemove,
        "VL-REMOVE-IF": vlRemoveIf,
        "VL-REMOVE-IF-NOT": vlRemoveIfNot,
        "VL-SORT": vlSort,
        "VL-SORT-I": vlSortI,
    ]

    // MARK: - Constructors

    private static func cons(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly("cons", args, 2)
        return .cons(head: args[0], tail: args[1])
    }

    private static func list(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        LispValue(list: args)
    }

    // MARK: - Accessors (nil-forgiving heads)

    private static func car(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly("car", args, 1)
        switch args[0] {
        case .nilValue: return .nilValue
        case let .cons(head, _): return head
        default: throw LispError.typeMismatch(name: "car", expected: "list", got: args[0])
        }
    }

    private static func cdr(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly("cdr", args, 1)
        switch args[0] {
        case .nilValue: return .nilValue
        case let .cons(_, tail): return tail
        default: throw LispError.typeMismatch(name: "cdr", expected: "list", got: args[0])
        }
    }

    /// Shared cadr/caddr: drops `depth` heads, nil-forgiving throughout.
    private static func cadr(depth: Int, name: String) -> LispBuiltin {
        { _, args, _, _ in
            try BuiltinArgs.exactly(name, args, 1)
            var cursor = args[0]
            for _ in 0..<depth {
                switch cursor {
                case .nilValue: return .nilValue
                case let .cons(_, tail): cursor = tail
                default: return .nilValue
                }
            }
            switch cursor {
            case .nilValue: return .nilValue
            case let .cons(head, _): return head
            default: return .nilValue
            }
        }
    }

    private static func last(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly("last", args, 1)
        let items = try BuiltinArgs.properList("last", args[0])
        // AutoLISP last returns the final ELEMENT, unlike Common
        // Lisp (which returns the last cons). Oracle: (last '(1 2 3)).
        guard let final = items.last else { return .nilValue }
        return final
    }

    private static func length(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly("length", args, 1)
        return .int(try BuiltinArgs.properList("length", args[0]).count)
    }

    private static func nth(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly("nth", args, 2)
        let index: Int = {
            switch args[0] {
            case let .int(v): return v
            case let .real(v): return Int(v)
            default: return -1
            }
        }()
        let items = try BuiltinArgs.properList("nth", args[1])
        guard index >= 0, index < items.count else { return .nilValue }
        return items[index]
    }

    // MARK: - Combination

    private static func append(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        guard !args.isEmpty else { return .nilValue }
        // All but the last must be proper lists; the last becomes the tail
        // (an atom last arg yields a dotted result).
        var heads: [LispValue] = []
        for arg in args.dropLast() {
            heads.append(contentsOf: try BuiltinArgs.properList("append", arg))
        }
        var out = args.last!
        for head in heads.reversed() { out = .cons(head: head, tail: out) }
        return out
    }

    private static func reverse(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly("reverse", args, 1)
        return LispValue(list: try BuiltinArgs.properList("reverse", args[0]).reversed())
    }

    private static func member(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly("member", args, 2)
        var cursor = args[1]
        while true {
            switch cursor {
            case .nilValue: return .nilValue
            case let .cons(head, tail):
                if LogicBuiltins.deepEqual(head, args[0], fuzz: nil) { return cursor }
                cursor = tail
            default:
                return .nilValue
            }
        }
    }

    private static func assoc(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly("assoc", args, 2)
        var cursor = args[1]
        while true {
            switch cursor {
            case .nilValue: return .nilValue
            case let .cons(head, tail):
                // Non-cons elements are skipped (entget lists stay well-formed).
                if case let .cons(key, _) = head,
                    LogicBuiltins.deepEqual(key, args[0], fuzz: nil)
                {
                    return head
                }
                cursor = tail
            default:
                return .nilValue
            }
        }
    }

    /// Recursive substitute: every equal occurrence at any depth.
    private static func subst(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly("subst", args, 3)
        return substIn(new: args[0], old: args[1], node: args[2])
    }

    private static func substIn(new newValue: LispValue, old: LispValue, node: LispValue) -> LispValue {
        if LogicBuiltins.deepEqual(node, old, fuzz: nil) { return newValue }
        if case let .cons(head, tail) = node {
            return .cons(head: substIn(new: newValue, old: old, node: head),
                tail: substIn(new: newValue, old: old, node: tail))
        }
        return node
    }

    // MARK: - vl- list utilities

    private static func vlListStar(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.range("vl-list*", args, min: 1)
        var out = args.last!
        for head in args.dropLast().reversed() { out = .cons(head: head, tail: out) }
        return out
    }

    private static func vlListLength(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly("vl-list-length", args, 1)
        guard let items = args[0].properList else { return .nilValue }
        return .int(items.count)
    }

    private static func vlListToString(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly("vl-list->string", args, 1)
        let items = try BuiltinArgs.properList("vl-list->string", args[0])
        var out = ""
        for item in items {
            guard case let .int(code) = item,
                let scalar = UnicodeScalar(code)
            else {
                throw LispError.typeMismatch(name: "vl-list->string", expected: "char-code list", got: args[0])
            }
            out.append(Character(scalar))
        }
        return .string(out)
    }

    private static func vlConsp(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly("vl-consp", args, 1)
        if case .cons = args[0] { return .t }
        return .nilValue
    }

    private static func callPredicate(
        _ eval: LispEvaluator, _ fn: LispValue, _ args: [LispValue],
        env: inout LispEnvironment, host: any LispHost
    ) async throws -> LispValue {
        try await eval.applyValue(fn, args: args, env: &env, host: host, depth: 0)
    }

    private static func vlEvery(
        eval: LispEvaluator, args: [LispValue], env: inout LispEnvironment, host: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.range("vl-every", args, min: 2)
        let lists = try args.dropFirst().map { try BuiltinArgs.properList("vl-every", $0) }
        let shortest = lists.map(\.count).min() ?? 0
        var last: LispValue = .t
        for index in 0..<shortest {
            last = try await callPredicate(eval, args[0], lists.map { $0[index] }, env: &env, host: host)
            if !last.isTrue { return .nilValue }
        }
        return last
    }

    private static func vlSome(
        eval: LispEvaluator, args: [LispValue], env: inout LispEnvironment, host: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.range("vl-some", args, min: 2)
        let lists = try args.dropFirst().map { try BuiltinArgs.properList("vl-some", $0) }
        let shortest = lists.map(\.count).min() ?? 0
        for index in 0..<shortest {
            let value = try await callPredicate(eval, args[0], lists.map { $0[index] }, env: &env, host: host)
            if value.isTrue { return value }
        }
        return .nilValue
    }

    private static func vlMemberIf(
        eval: LispEvaluator, args: [LispValue], env: inout LispEnvironment, host: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly("vl-member-if", args, 2)
        var cursor = args[1]
        while true {
            switch cursor {
            case .nilValue: return .nilValue
            case let .cons(head, tail):
                let verdict = try await callPredicate(eval, args[0], [head], env: &env, host: host)
                if verdict.isTrue { return cursor }
                cursor = tail
            default: return .nilValue
            }
        }
    }

    private static func vlMemberIfNot(
        eval: LispEvaluator, args: [LispValue], env: inout LispEnvironment, host: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly("vl-member-if-not", args, 2)
        var cursor = args[1]
        while true {
            switch cursor {
            case .nilValue: return .nilValue
            case let .cons(head, tail):
                let verdict = try await callPredicate(eval, args[0], [head], env: &env, host: host)
                if !verdict.isTrue { return cursor }
                cursor = tail
            default: return .nilValue
            }
        }
    }

    private static func vlPosition(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly("vl-position", args, 2)
        let items = try BuiltinArgs.properList("vl-position", args[1])
        for (index, item) in items.enumerated() {
            if LogicBuiltins.deepEqual(item, args[0], fuzz: nil) { return .int(index) }
        }
        return .nilValue
    }

    private static func filterList(
        eval: LispEvaluator, name: String, args: [LispValue], keep: Bool,
        env: inout LispEnvironment, host: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly(name, args, 2)
        let items = try BuiltinArgs.properList(name, args[1])
        if name == "vl-remove" {
            return LispValue(list: items.filter {
                LogicBuiltins.deepEqual($0, args[0], fuzz: nil) == keep
            })
        }
        var out: [LispValue] = []
        for item in items {
            let verdict = try await callPredicate(eval, args[0], [item], env: &env, host: host)
            if verdict.isTrue == keep { out.append(item) }
        }
        return LispValue(list: out)
    }

    private static func vlRemove(
        eval: LispEvaluator, args: [LispValue], env: inout LispEnvironment, host: any LispHost
    ) async throws -> LispValue {
        try await filterList(eval: eval, name: "vl-remove", args: args, keep: false, env: &env, host: host)
    }

    private static func vlRemoveIf(
        eval: LispEvaluator, args: [LispValue], env: inout LispEnvironment, host: any LispHost
    ) async throws -> LispValue {
        try await filterList(eval: eval, name: "vl-remove-if", args: args, keep: false, env: &env, host: host)
    }

    private static func vlRemoveIfNot(
        eval: LispEvaluator, args: [LispValue], env: inout LispEnvironment, host: any LispHost
    ) async throws -> LispValue {
        try await filterList(eval: eval, name: "vl-remove-if-not", args: args, keep: true, env: &env, host: host)
    }

    // NOTE: vl-sort/vl-sort-i take (list pred), unlike the pred-first
    // vl-member-if/vl-remove-if family. AutoCAD's order, kept as-is.
    private static func vlSort(
        eval: LispEvaluator, args: [LispValue], env: inout LispEnvironment, host: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly("vl-sort", args, 2)
        let items = try BuiltinArgs.properList("vl-sort", args[0])
        // Insertion sort (stable): predicate is an async call, so no stdlib sort.
        var out = items
        for index in 1..<out.count {
            var hole = index
            while hole > 0 {
                let before = try await callPredicate(
                    eval, args[1], [out[hole], out[hole - 1]], env: &env, host: host)
                guard before.isTrue else { break }
                out.swapAt(hole, hole - 1)
                hole -= 1
            }
        }
        return LispValue(list: out)
    }

    private static func vlSortI(
        eval: LispEvaluator, args: [LispValue], env: inout LispEnvironment, host: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly("vl-sort-i", args, 2)
        let items = try BuiltinArgs.properList("vl-sort-i", args[0])
        var order = Array(items.indices)
        for index in 1..<order.count {
            var hole = index
            while hole > 0 {
                let before = try await callPredicate(
                    eval, args[1], [items[order[hole]], items[order[hole - 1]]],
                    env: &env, host: host)
                guard before.isTrue else { break }
                order.swapAt(hole, hole - 1)
                hole -= 1
            }
        }
        return LispValue(list: order.map(LispValue.int))
    }
}
