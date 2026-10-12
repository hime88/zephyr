// FileBuiltins: Wave-B text file IO (open/close/read-char/read-line/
// write-char/write-line).
//
// File descriptors are small integers minted by open (monotonic, never
// recycled). Read-mode files buffer fully at open; write-mode calls go
// straight to disk, so data survives even if close is skipped. Paths are
// used as given (relative paths resolve against the process working
// directory); open failures return nil, never throw. Without a descriptor,
// read/write target the console through the host (line-buffered reads).
import Foundation

enum FileBuiltins {
    static let table: [String: LispBuiltin] = [
        "OPEN": openFile,
        "CLOSE": closeFile,
        "READ-CHAR": readChar,
        "READ-LINE": readLine,
        "WRITE-CHAR": writeChar,
        "WRITE-LINE": writeLine,
    ]

    private static func openFile(
        _: LispEvaluator, args: [LispValue], env: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly("open", args, 2)
        let path = try BuiltinArgs.string("open", args[0])
        let mode = try BuiltinArgs.string("open", args[1]).lowercased()
        guard mode == "r" || mode == "w" || mode == "a" else { return .nilValue }
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        switch mode {
        case "r":
            guard let text = try? String(contentsOf: url, encoding: .utf8) else {
                return .nilValue
            }
            let id = env.nextFileID
            env.nextFileID += 1
            env.openFiles[id] = LispOpenFile(
                path: path, mode: mode, chars: Array(text))
            return .int(id)
        case "w":
            guard (try? "".write(to: url, atomically: true, encoding: .utf8)) != nil else {
                return .nilValue
            }
            let id = env.nextFileID
            env.nextFileID += 1
            env.openFiles[id] = LispOpenFile(path: path, mode: mode)
            return .int(id)
        default: // "a"
            if !FileManager.default.fileExists(atPath: url.path) {
                guard (try? "".write(to: url, atomically: true, encoding: .utf8)) != nil else {
                    return .nilValue
                }
            }
            let id = env.nextFileID
            env.nextFileID += 1
            env.openFiles[id] = LispOpenFile(path: path, mode: mode)
            return .int(id)
        }
    }

    private static func closeFile(
        _: LispEvaluator, args: [LispValue], env: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly("close", args, 1)
        if case let .int(id) = args[0] {
            env.openFiles.removeValue(forKey: id)
        }
        return .nilValue
    }

    /// Resolves an optional descriptor argument: nil when omitted (console),
    /// the open file for an integer id, or throws for a bad descriptor.
    private static func fileForRead(
        _ name: String, args: [LispValue], env: LispEnvironment
    ) throws -> (id: Int, file: LispOpenFile)? {
        guard !args.isEmpty else { return nil }
        guard case let .int(id) = args[0], let file = env.openFiles[id] else {
            throw LispError.hostError("\(name): invalid file descriptor")
        }
        guard file.mode == "r" else {
            throw LispError.hostError("\(name): file is not open for reading")
        }
        return (id, file)
    }

    private static func fileForWrite(
        _ name: String, args: [LispValue], env: LispEnvironment
    ) throws -> (id: Int, file: LispOpenFile)? {
        try BuiltinArgs.range(name, args, min: 1, max: 2)
        guard args.count == 2 else { return nil }
        guard case let .int(id) = args[1],
              let file = env.openFiles[id]
        else {
            throw LispError.hostError("\(name): invalid file descriptor")
        }
        guard file.mode == "w" || file.mode == "a" else {
            throw LispError.hostError("\(name): file is not open for writing")
        }
        return (id, file)
    }

    private static func readChar(
        _: LispEvaluator, args: [LispValue], env: inout LispEnvironment, host: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.range("read-char", args, min: 0, max: 1)
        guard let (id, opened) = try fileForRead("read-char", args: args, env: env) else {
            // Console: first character of a typed line (line-buffered).
            guard let line = try await host.requestLine(prompt: "") else { return .nilValue }
            guard let first = line.first,
                  let scalar = first.unicodeScalars.first
            else { return .nilValue }
            return .int(Int(scalar.value))
        }
        var file = opened
        guard !file.atEOF else { return .nilValue }
        let char = file.chars[file.offset]
        file.offset += 1
        env.openFiles[id] = file
        return .int(Int(char.unicodeScalars.first?.value ?? 0))
    }

    private static func readLine(
        _: LispEvaluator, args: [LispValue], env: inout LispEnvironment, host: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.range("read-line", args, min: 0, max: 1)
        guard let (id, opened) = try fileForRead("read-line", args: args, env: env) else {
            guard let line = try await host.requestLine(prompt: "") else {
                return .string("")
            }
            return .string(line)
        }
        var file = opened
        guard !file.atEOF else { return .nilValue }
        var out = ""
        while file.offset < file.chars.count {
            let char = file.chars[file.offset]
            file.offset += 1
            if char == "\n" { break }
            out.append(char)
        }
        if out.hasSuffix("\r") { out.removeLast() }
        env.openFiles[id] = file
        return .string(out)
    }

    private static func writeChar(
        _: LispEvaluator, args: [LispValue], env: inout LispEnvironment, host: any LispHost
    ) async throws -> LispValue {
        let target = try fileForWrite("write-char", args: args, env: env)
        let code = try BuiltinArgs.int("write-char", args[0])
        guard code >= 0, let scalar = UnicodeScalar(code) else {
            throw LispError.hostError("write-char: invalid character code \(code)")
        }
        let text = String(Character(scalar))
        if let (_, file) = target {
            try appendToFile(file: file, text: text, name: "write-char")
        } else {
            await host.write(text)
        }
        return .int(code)
    }

    private static func writeLine(
        _: LispEvaluator, args: [LispValue], env: inout LispEnvironment, host: any LispHost
    ) async throws -> LispValue {
        let target = try fileForWrite("write-line", args: args, env: env)
        let text = try BuiltinArgs.string("write-line", args[0])
        if let (_, file) = target {
            try appendToFile(file: file, text: text + "\n", name: "write-line")
        } else {
            await host.write(text + "\n")
        }
        return .string(text)
    }

    private static func appendToFile(file: LispOpenFile, text: String, name: String) throws {
        let url = URL(fileURLWithPath: (file.path as NSString).expandingTildeInPath)
        guard let data = text.data(using: .utf8) else {
            throw LispError.hostError("\(name): cannot encode output")
        }
        do {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            // Both modes append in call order ("w" truncated at open).
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            throw LispError.hostError("\(name): write failed: \(error.localizedDescription)")
        }
    }
}
