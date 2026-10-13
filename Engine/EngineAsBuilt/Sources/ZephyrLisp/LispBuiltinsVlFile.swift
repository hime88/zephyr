// VlFileBuiltins: Wave-C vl-file-* + vl-mkdir + vl-directory-files +
// vl-bb-ref/vl-bb-set. Thin Foundation bindings; failures return nil,
// never throw (except arity/type misuse).
import Foundation

enum VlFileBuiltins {
    static let table: [String: LispBuiltin] = [
        "VL-FILE-COPY": vlFileCopy,
        "VL-FILE-DELETE": vlFileDelete,
        "VL-FILE-DIRECTORY-P": vlFileDirectoryP,
        "VL-FILE-RENAME": vlFileRename,
        "VL-FILE-SIZE": vlFileSize,
        "VL-FILE-SYSTIME": vlFileSystime,
        "VL-MKDIR": vlMkdir,
        "VL-DIRECTORY-FILES": vlDirectoryFiles,
        "VL-BB-REF": vlBbRef,
        "VL-BB-SET": vlBbSet,
    ]

    private static func expand(_ path: String) -> String {
        (path as NSString).expandingTildeInPath
    }

    private static func vlFileCopy(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.range("vl-file-copy", args, min: 2, max: 3)
        let src = expand(try BuiltinArgs.string("vl-file-copy", args[0]))
        let dst = expand(try BuiltinArgs.string("vl-file-copy", args[1]))
        let append = args.count == 3 && args[2].isTrue
        guard let data = FileManager.default.contents(atPath: src) else {
            return .nilValue
        }
        do {
            if append, FileManager.default.fileExists(atPath: dst) {
                let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: dst))
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } else {
                if FileManager.default.fileExists(atPath: dst) {
                    try FileManager.default.removeItem(atPath: dst)
                }
                try data.write(to: URL(fileURLWithPath: dst))
            }
            return .int(data.count)
        } catch {
            return .nilValue
        }
    }

    private static func vlFileDelete(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly("vl-file-delete", args, 1)
        let path = expand(try BuiltinArgs.string("vl-file-delete", args[0]))
        do {
            try FileManager.default.removeItem(atPath: path)
            return .t
        } catch {
            return .nilValue
        }
    }

    private static func vlFileDirectoryP(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly("vl-file-directory-p", args, 1)
        let path = expand(try BuiltinArgs.string("vl-file-directory-p", args[0]))
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir) else {
            return .nilValue
        }
        return isDir.boolValue ? .t : .nilValue
    }

    private static func vlFileRename(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly("vl-file-rename", args, 2)
        let old = expand(try BuiltinArgs.string("vl-file-rename", args[0]))
        let new = expand(try BuiltinArgs.string("vl-file-rename", args[1]))
        do {
            try FileManager.default.moveItem(atPath: old, toPath: new)
            return .t
        } catch {
            return .nilValue
        }
    }

    private static func vlFileSize(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly("vl-file-size", args, 1)
        let path = expand(try BuiltinArgs.string("vl-file-size", args[0]))
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attrs[.size] as? Int
        else {
            return .nilValue
        }
        return .int(size)
    }

    private static func vlFileSystime(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly("vl-file-systime", args, 1)
        let path = expand(try BuiltinArgs.string("vl-file-systime", args[0]))
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let date = attrs[.modificationDate] as? Date
        else {
            return .nilValue
        }
        let parts = Calendar.current.dateComponents(
            [.year, .month, .weekday, .day, .hour, .minute, .second, .nanosecond],
            from: date)
        return LispValue(list: [
            .int(parts.year ?? 0), .int(parts.month ?? 0),
            .int(parts.weekday ?? 0), .int(parts.day ?? 0),
            .int(parts.hour ?? 0), .int(parts.minute ?? 0),
            .int(parts.second ?? 0),
            .int((parts.nanosecond ?? 0) / 1_000_000),
        ])
    }

    private static func vlMkdir(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly("vl-mkdir", args, 1)
        let path = expand(try BuiltinArgs.string("vl-mkdir", args[0]))
        do {
            try FileManager.default.createDirectory(
                atPath: path, withIntermediateDirectories: true)
            return .t
        } catch {
            return .nilValue
        }
    }

    private static func vlDirectoryFiles(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.range("vl-directory-files", args, min: 0, max: 3)
        func optionalString(_ index: Int, _ name: String) throws -> String? {
            guard args.count > index, !args[index].isNil else { return nil }
            return try BuiltinArgs.string(name, args[index])
        }
        let path = expand(
            (try optionalString(0, "vl-directory-files"))
                ?? FileManager.default.currentDirectoryPath)
        let pattern = (try optionalString(1, "vl-directory-files")) ?? "*"
        let includeDirs = args.count > 2 && args[2].isTrue
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: path) else {
            return .nilValue
        }
        var out: [String] = []
        for name in names {
            var isDir: ObjCBool = false
            let full = (path as NSString).appendingPathComponent(name)
            _ = FileManager.default.fileExists(atPath: full, isDirectory: &isDir)
            if isDir.boolValue, !includeDirs { continue }
            if Wildcard.matchAlternatives(text: Array(name), pattern: pattern) {
                out.append(name)
            }
        }
        guard !out.isEmpty else { return .nilValue }
        return LispValue(stringList: out.sorted())
    }

    private static func vlBbRef(
        _: LispEvaluator, args: [LispValue], env: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly("vl-bb-ref", args, 1)
        return env.blackboard[try BuiltinArgs.symbol("vl-bb-ref", args[0])] ?? .nilValue
    }

    private static func vlBbSet(
        _: LispEvaluator, args: [LispValue], env: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly("vl-bb-set", args, 2)
        let name = try BuiltinArgs.symbol("vl-bb-set", args[0])
        env.blackboard[name] = args[1]
        return args[1]
    }
}
