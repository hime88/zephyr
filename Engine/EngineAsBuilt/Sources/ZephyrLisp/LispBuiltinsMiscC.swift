// MiscCBuiltins: Wave-C portable miscellany — getcfg/setcfg,
// getcname, mem, initcommandversion, setfunhelp, acdimenableupdate,
// acet-layerp-*, acet-ms/ps-to-*, initdia, help, startapp.
import Foundation

/// One setfunhelp registration.
public struct LispFunHelp: Sendable, Equatable {
    public let file: String
    public let topic: String

    public init(file: String, topic: String) {
        self.file = file
        self.topic = topic
    }
}

enum MiscCBuiltins {
    static let table: [String: LispBuiltin] = [
        "GETCFG": getcfg,
        "SETCFG": setcfg,
        "GETCNAME": getcname,
        "MEM": mem,
        "INITCOMMANDVERSION": initCommandVersion,
        "SETFUNHELP": setfunhelp,
        "ACDIMENABLEUPDATE": acdimEnableUpdate,
        "ACET-LAYERP-MARK": acetLayerpMark,
        "ACET-LAYERP-MODE": acetLayerpMode,
        "ACET-MS-TO-PS": acetMsToPs,
        "ACET-PS-TO-MS": acetPsToMs,
        "INITDIA": initdia,
        "HELP": help,
        "ACAD_HELPDLG": acadHelpdlg,
        "STARTAPP": startapp,
    ]

    private static let cfgNamespace = "ZephyrLispCfg."

    private static func getcfg(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly("getcfg", args, 1)
        let section = try BuiltinArgs.string("getcfg", args[0])
        guard let value = UserDefaults.standard.string(
            forKey: "\(cfgNamespace)\(section)") else {
            return .nilValue
        }
        return .string(value)
    }

    private static func setcfg(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly("setcfg", args, 2)
        let section = try BuiltinArgs.string("setcfg", args[0])
        let value = try BuiltinArgs.string("setcfg", args[1])
        UserDefaults.standard.set(value, forKey: "\(cfgNamespace)\(section)")
        return .string(value)
    }

    /// (getcname "_LINE") returns the canonical command name. Zephyr
    /// has no command localization, so this strips the underscore
    /// prefix and returns the name as-is.
    private static func getcname(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly("getcname", args, 1)
        var name = try BuiltinArgs.string("getcname", args[0])
        if name.hasPrefix("_") { name = String(name.dropFirst()) }
        guard !name.isEmpty else { return .nilValue }
        return .string(name)
    }

    /// (mem) prints a one-line memory summary and returns nil.
    private static func mem(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, host: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly("mem", args, 0)
        let megabytes = ProcessInfo.processInfo.physicalMemory / 1024 / 1024
        await host.write("physical memory: \(megabytes) MB\n")
        return .nilValue
    }

    private static func initCommandVersion(
        _: LispEvaluator, args: [LispValue], env: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.range("initcommandversion", args, min: 0, max: 1)
        if !args.isEmpty {
            env.commandVersion = try BuiltinArgs.int("initcommandversion", args[0])
        }
        return .t
    }

    /// (setfunhelp cmd file topic) records a help mapping and returns
    /// the previously registered topic, or nil.
    private static func setfunhelp(
        _: LispEvaluator, args: [LispValue], env: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly("setfunhelp", args, 3)
        let name = try BuiltinArgs.string("setfunhelp", args[0]).uppercased()
        let file = try BuiltinArgs.string("setfunhelp", args[1])
        let topic = try BuiltinArgs.string("setfunhelp", args[2])
        let prior = env.funHelp[name]?.topic
        env.funHelp[name] = LispFunHelp(file: file, topic: topic)
        return prior.map(LispValue.string) ?? .nilValue
    }

    private static func acdimEnableUpdate(
        _: LispEvaluator, args: [LispValue], env: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly("acdimenableupdate", args, 1)
        env.dimUpdateEnabled = args[0].isTrue
        return args[0].isTrue ? .t : .nilValue
    }

    private static func acetLayerpMark(
        _: LispEvaluator, args: [LispValue], env: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.range("acet-layerp-mark", args, min: 0, max: 1)
        if args.isEmpty || args[0].isTrue {
            env.layerpDepth += 1
        } else {
            env.layerpDepth = max(0, env.layerpDepth - 1)
        }
        return .t
    }

    private static func acetLayerpMode(
        _: LispEvaluator, args: [LispValue], env: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.range("acet-layerp-mode", args, min: 0, max: 1)
        if !args.isEmpty {
            env.layerpMode = args[0].isTrue
        }
        return env.layerpMode ? .t : .nilValue
    }

    /// Model/paper scale conversion. Zephyr is a single-view host with
    /// no viewport scales, so the scale factor is 1.0 and both
    /// directions are the identity (documented, not silent: the
    /// viewport argument Express Tools read does not exist here).
    private static func acetMsToPs(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly("acet-ms-to-ps", args, 1)
        return .real(try BuiltinArgs.number("acet-ms-to-ps", args[0]))
    }

    private static func acetPsToMs(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly("acet-ps-to-ms", args, 1)
        return .real(try BuiltinArgs.number("acet-ps-to-ms", args[0]))
    }

    private static func initdia(
        _: LispEvaluator, args: [LispValue], env: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.range("initdia", args, min: 0, max: 1)
        if !args.isEmpty {
            env.initDiaFlag = try BuiltinArgs.int("initdia", args[0])
        }
        return .nilValue
    }

    /// No help viewer exists on this host: help always returns nil,
    /// like AutoCAD with no help file installed.
    private static func help(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.range("help", args, min: 0, max: 3)
        for arg in args {
            _ = try BuiltinArgs.string("help", arg)
        }
        return .nilValue
    }

    private static func acadHelpdlg(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.exactly("acad_helpdlg", args, 2)
        _ = try BuiltinArgs.string("acad_helpdlg", args[0])
        _ = try BuiltinArgs.string("acad_helpdlg", args[1])
        return .nilValue
    }

    /// (startapp app [file]) launches an external program without
    /// waiting and returns its process id, or nil on failure.
    private static func startapp(
        _: LispEvaluator, args: [LispValue], _: inout LispEnvironment, _: any LispHost
    ) async throws -> LispValue {
        try BuiltinArgs.range("startapp", args, min: 1, max: 2)
        let app = try BuiltinArgs.string("startapp", args[0])
        var file: String?
        if args.count == 2 {
            file = try BuiltinArgs.string("startapp", args[1])
        }
        do {
            let process = Process()
            #if os(Windows)
                guard let exeURL = resolveWindowsExecutable(app) else {
                    return .nilValue
                }
                process.executableURL = exeURL
                process.arguments = file.map { [$0] }
            #else
                var command = "exec \(shellQuote(app))"
                if let file {
                    command += " \(shellQuote(file))"
                }
                process.executableURL = URL(fileURLWithPath: "/bin/sh")
                process.arguments = ["-c", command]
            #endif
            try process.run()
            return .int(Int(process.processIdentifier))
        } catch {
            return .nilValue
        }
    }

    #if os(Windows)
    private static func resolveWindowsExecutable(_ app: String) -> URL? {
        if FileManager.default.fileExists(atPath: app) {
            return URL(fileURLWithPath: app)
        }
        let env = ProcessInfo.processInfo.environment
        var searchDirs: [String] = []
        if let path = env["PATH"] {
            searchDirs.append(contentsOf: path.split(separator: ";").map(String.init))
        }
        if let systemRoot = env["SystemRoot"] {
            searchDirs.append("\(systemRoot)\\System32")
        }
        let extensions: [String]
        if app.contains(".") {
            extensions = [""]
        } else {
            let pathext = env["PATHEXT"] ?? ".COM;.EXE;.BAT;.CMD"
            extensions = pathext.split(separator: ";").map(String.init)
        }
        for dir in searchDirs {
            for ext in extensions {
                let candidate = (dir as NSString).appendingPathComponent(app + ext)
                if FileManager.default.fileExists(atPath: candidate) {
                    return URL(fileURLWithPath: candidate)
                }
            }
        }
        return nil
    }
    #endif

    private static func shellQuote(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
