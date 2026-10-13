// EnvBuiltins: Wave-B environment + filename + misc builtins
// (alloc/expand/gc/getenv/setenv/findfile/findtrustedfile/
// vl-filename-base/vl-filename-directory/vl-filename-extension/
// vl-filename-mktemp/vl-propagate/vports/xdroom/xdsize).
//
// All process-local except xdroom (entity xdata via the host).
import Foundation
#if os(Windows)
import WinSDK
import ucrt
#endif

public enum EnvBuiltins {
    static let table: [String: LispBuiltin] = [
        "ALLOC": alloc,
        "EXPAND": expand,
        "GC": gc,
        "GETENV": getenv,
        "SETENV": setenv,
        "FINDFILE": findfile,
        "FINDTRUSTEDFILE": findtrustedfile,
        "VL-FILENAME-BASE": vlFilenameBase,
        "VL-FILENAME-DIRECTORY": vlFilenameDirectory,
        "VL-FILENAME-EXTENSION": vlFilenameExtension,
        "VL-FILENAME-MKTEMP": vlFilenameMktemp,
        "VL-PROPAGATE": vlPropagate,
        "VPORTS": vports,
        "XDROOM": xdroom,
        "XDSIZE": xdsize,
    ]

    private static func alloc(
        _: LispEvaluator, args: [LispValue], env: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly("alloc", args, 1)
        let size = try BuiltinArgs.int("alloc", args[0])
        let old = env.allocNodes
        env.allocNodes = max(0, size)
        return .int(old)
    }

    private static func expand(
        _: LispEvaluator, args: [LispValue], env: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly("expand", args, 1)
        let segments = try BuiltinArgs.int("expand", args[0])
        let old = env.expandSegments
        env.expandSegments = max(0, segments)
        return .int(old)
    }

    private static func gc(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.range("gc", args, min: 0, max: 0)
        return .nilValue // Swift ARC: nothing to collect.
    }

    private static func getenv(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly("getenv", args, 1)
        let name = try BuiltinArgs.string("getenv", args[0])
        guard let value = ProcessInfo.processInfo.environment[name] else {
            return .nilValue
        }
        return .string(value)
    }

    private static func setenv(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly("setenv", args, 2)
        let name = try BuiltinArgs.string("setenv", args[0])
        let value = try BuiltinArgs.string("setenv", args[1])
        #if canImport(Darwin)
        Darwin.setenv(name, value, 1)
        #elseif canImport(Glibc)
        Glibc.setenv(name, value, 1)
        #elseif os(Windows)
        _putenv_s(name, value)
        SetEnvironmentVariableA(name, value)
        #endif
        return .string(value)
    }

    private static func findfile(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly("findfile", args, 1)
        let name = try BuiltinArgs.string("findfile", args[0])
        return resolveSupportFile(name) ?? .nilValue
    }

    private static func findtrustedfile(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        // No trusted-paths concept exists: same resolution as findfile.
        try BuiltinArgs.exactly("findtrustedfile", args, 1)
        let name = try BuiltinArgs.string("findtrustedfile", args[0])
        return resolveSupportFile(name) ?? .nilValue
    }

    /// Resolves a support file: as-given (with ~ expansion), else against
    /// the process working directory. Returns the full path when found.
    private static func resolveSupportFile(_ name: String) -> LispValue? {
        let expanded = (name as NSString).expandingTildeInPath
        if FileManager.default.fileExists(atPath: expanded) {
            return .string(URL(fileURLWithPath: expanded).path)
        }
        let cwd = FileManager.default.currentDirectoryPath as NSString
        let joined = cwd.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: joined) {
            return .string(joined)
        }
        return nil
    }

    // MARK: - vl-filename-*

    /// Splits "dir/base.ext" tolerating both / and \ separators.
    private static func splitFilename(_ path: String) -> (dir: String, base: String, ext: String) {
        let separators = CharacterSet(charactersIn: "/\\")
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let lastSep = trimmed.rangeOfCharacter(
            from: separators, options: .backwards)
        else {
            return splitBase(trimmed, dir: "")
        }
        let dir = String(trimmed[..<lastSep.lowerBound])
        return splitBase(String(trimmed[lastSep.upperBound...]), dir: dir)
    }

    private static func splitBase(_ file: String, dir: String) -> (dir: String, base: String, ext: String) {
        if file.hasPrefix("."), !file.dropFirst().contains(".") {
            return (dir, file, "") // Dotfile, no extension.
        }
        guard let dot = file.range(of: ".", options: .backwards),
              dot.lowerBound != file.startIndex
        else {
            return (dir, file, "")
        }
        return (
            dir,
            String(file[..<dot.lowerBound]),
            String(file[dot.lowerBound...])) // Extension keeps its dot.
    }

    private static func vlFilenameBase(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly("vl-filename-base", args, 1)
        return .string(splitFilename(try BuiltinArgs.string("vl-filename-base", args[0])).base)
    }

    private static func vlFilenameDirectory(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly("vl-filename-directory", args, 1)
        return .string(
            splitFilename(try BuiltinArgs.string("vl-filename-directory", args[0])).dir)
    }

    private static func vlFilenameExtension(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly("vl-filename-extension", args, 1)
        return .string(
            splitFilename(try BuiltinArgs.string("vl-filename-extension", args[0])).ext)
    }

    private static func vlFilenameMktemp(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.range("vl-filename-mktemp", args, min: 0, max: 3)
        func optionalString(_ index: Int) throws -> String? {
            guard args.count > index, !args[index].isNil else { return nil }
            return try BuiltinArgs.string("vl-filename-mktemp", args[index])
        }
        let pattern = (try optionalString(0)) ?? "tmp"
        let directory = (try optionalString(1)) ?? FileManager.default.temporaryDirectory.path
        var ext = (try optionalString(2)) ?? ".tmp"
        if !ext.isEmpty, !ext.hasPrefix(".") { ext = "." + ext }
        let unique = "\(pattern)_\(ProcessInfo.processInfo.processIdentifier)_\(Int.random(in: 0...Int.max))"
        return .string((directory as NSString).appendingPathComponent(unique + ext))
    }

    private static func vlPropagate(
        _: LispEvaluator, args: [LispValue], env: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        // Single document/namespace: the symbol is already visible.
        try BuiltinArgs.exactly("vl-propagate", args, 1)
        _ = try BuiltinArgs.symbol("vl-propagate", args[0])
        _ = env
        return .nilValue
    }

    private static func vports(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.range("vports", args, min: 0, max: 0)
        // Single viewport covering the full view (normalized corners).
        return LispValue(list: [
            LispValue(list: [
                LispValue(list: [.real(0), .real(0)]),
                LispValue(list: [.real(1), .real(1)]),
            ]),
        ])
    }

    // MARK: - xdata sizing

    /// Maximum xdata payload per entity (AutoCAD-compatible budget).
    public static let xdataBudget = 16368

    private static func xdroom(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, host: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly("xdroom", args, 1)
        guard case let .entityName(handle) = args[0] else {
            throw LispError.typeMismatch(
                name: "xdroom", expected: "entity name", got: args[0])
        }
        return .int(try await host.xdataRoom(handle))
    }

    private static func xdsize(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly("xdsize", args, 1)
        guard let items = args[0].properList else {
            throw LispError.typeMismatch(
                name: "xdsize", expected: "xdata list", got: args[0])
        }
        var total = 0
        for item in items {
            guard case let .cons(head, tail) = item,
                  head.asDouble != nil
            else {
                throw LispError.typeMismatch(
                    name: "xdsize", expected: "dotted xdata pair", got: item)
            }
            total += 8 + payloadSize(tail) // Group overhead + payload.
        }
        return .int(total)
    }

    /// Documented rough payload sizing (matches the host's xdataRoom math).
    static func payloadSize(_ value: LispValue) -> Int {
        switch value {
        case .int: return 8
        case .real: return 8
        case let .string(s): return s.utf8.count + 1
        case let .symbol(s): return s.utf8.count + 1
        case let .cons(head, tail):
            return 8 + payloadSize(head) + payloadSize(tail)
        case .nilValue: return 1
        case .entityName, .selectionSet, .errorObject, .vlaObject: return 16
        }
    }
}
