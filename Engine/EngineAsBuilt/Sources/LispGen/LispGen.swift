// LispGen: inventory extractor + registry code generator.
//
// Reads Tools/lisp/autolisp.html (embedded {n,d,p,s,r,pr,ex} records),
// scans Tools/lisp/corpus/*.lsp for referenced builtins, assigns each of
// the 305 entries a disposition, and writes the generated Swift registry.
//
// Usage (from Engine/EngineAsBuilt):
//   swift run LispGen \
//     --input Tools/lisp/autolisp.html \
//     --corpus Tools/lisp/corpus \
//     --output Sources/ZephyrLisp/Generated/LispRegistry.generated.swift
//
// Exit codes: 0 on success; 1 on any integrity failure (wrong entry count,
// duplicates, missing keys, unknown wave/stub name, corpus referencing a
// stubbed builtin, unreadable input). No Regex, no Clock/Duration, no Span:
// this tool and its output stay macOS 12 clean.
import Foundation

// MARK: - Disposition policy (explicit sets; everything else is rule-based)

/// Builtins with no portable implementation. Each gets a clean-error stub
/// plus a test asserting that error. ARX/VLX/VBA loading, tablet/menu/text
/// page UI surfaces, and two Express Tools with no host equivalent.
let stubNames: Set<String> = [
    "arx", "arxload", "arxunload", "autoarxload", "vl-arx-import",
    "vl-list-loaded-vlx", "vl-load-all", "vl-unload-vlx",
    "vl-vbaload", "vl-vbarun", "vl-vlx-loaded-p",
    "tablet", "menucmd", "menugroup", "textpage",
    "acet-laytrans", "showhtmlmodalwindow",
]

/// Wave A: interactive core + language core. Anything the seed corpus
/// references (outside the stub set) is promoted here automatically.
let waveACoreNames: Set<String> = [
    // Special forms / language core.
    "defun", "defun-q", "lambda", "quote", "if", "cond", "while",
    "repeat", "foreach", "progn", "setq", "set", "apply", "mapcar",
    "eval", "and", "or", "not",
    // Error handling.
    "*error*", "*pop-error-mode*", "*push-error-using-command*",
    "*push-error-using-stack*", "vl-catch-all-apply",
    "vl-catch-all-error-message", "vl-catch-all-error-p",
    // Entity access.
    "entdel", "entget", "entlast", "entmake", "entmakex", "entmod",
    "entnext", "entsel", "nentsel", "nentselp", "entupd", "handent",
    // Selection sets.
    "ssget", "ssadd", "ssdel", "sslength", "ssname", "ssmemb",
    "ssgetfirst", "sssetfirst",
    // Command invocation.
    "command", "command-s", "vl-cmdf",
    // System variables.
    "getvar", "setvar",
    // User input.
    "getangle", "getcorner", "getdist", "getint", "getkword",
    "getorient", "getpoint", "getreal", "getstring", "initget", "grread",
    // Point math.
    "angle", "distance", "polar",
    // Display.
    "princ", "prin1", "print", "prompt", "terpri",
    // Loading / version.
    "load", "autoload", "ver",
]

// MARK: - Record model

struct RawEntry {
    var n = ""
    var d = ""
    var p = ""
    var s = ""
    var r = ""
    var pr = ""
    var ex = ""
    var hasEx = false
}

enum Disposition: String {
    case waveA, waveB, waveC, stub
}

// MARK: - HTML record scanner (no Regex: macOS 12 floor)

/// Decodes one JS string literal body starting after the opening quote.
/// Returns the decoded value and the index just past the closing quote.
func scanJSONString(_ text: String, from start: String.Index) -> (String, String.Index)? {
    var out = ""
    var i = start
    while i < text.endIndex {
        let ch = text[i]
        if ch == "\\" {
            let nxt = text.index(after: i)
            guard nxt < text.endIndex else { return nil }
            switch text[nxt] {
            case "n": out.append("\n")
            case "t": out.append("\t")
            case "r": out.append("\r")
            case "\"": out.append("\"")
            case "\\": out.append("\\")
            default: out.append(text[nxt])
            }
            i = text.index(after: nxt)
        } else if ch == "\"" {
            return (out, text.index(after: i))
        } else {
            out.append(ch)
            i = text.index(after: i)
        }
    }
    return nil
}

func skipWhitespace(_ text: String, from start: String.Index) -> String.Index {
    var i = start
    while i < text.endIndex, text[i].isWhitespace { i = text.index(after: i) }
    return i
}

func scanRecords(_ html: String) throws -> [RawEntry] {
    var entries: [RawEntry] = []
    var search = html.startIndex
    while let found = html.range(of: "{n: \"", range: search..<html.endIndex) {
        var entry = RawEntry()
        var i = found.upperBound
        var keysSeen: Set<String> = []
        // First pair is always n (marker consumed the key + opening quote).
        guard let (name, afterName) = scanJSONString(html, from: i) else {
            throw GenError("unterminated n value at offset \(html.distance(from: html.startIndex, to: i))")
        }
        entry.n = name
        keysSeen.insert("n")
        i = afterName
        var closed = false
        while i < html.endIndex {
            i = skipWhitespace(html, from: i)
            guard i < html.endIndex else { break }
            if html[i] == "}" { closed = true; i = html.index(after: i); break }
            guard html[i] == "," else { throw GenError("expected , or } in record \(name)") }
            i = skipWhitespace(html, from: html.index(after: i))
            // key
            var key = ""
            while i < html.endIndex, html[i] != ":" {
                key.append(html[i])
                i = html.index(after: i)
            }
            key = key.trimmingCharacters(in: .whitespaces)
            guard i < html.endIndex else { throw GenError("truncated record \(name)") }
            i = skipWhitespace(html, from: html.index(after: i)) // past ':'
            guard i < html.endIndex, html[i] == "\"" else {
                throw GenError("expected string value for key \(key) in record \(name)")
            }
            guard let (value, afterValue) = scanJSONString(html, from: html.index(after: i)) else {
                throw GenError("unterminated value for key \(key) in record \(name)")
            }
            switch key {
            case "d": entry.d = value
            case "p": entry.p = value
            case "s": entry.s = value
            case "r": entry.r = value
            case "pr": entry.pr = value
            case "ex": entry.ex = value; entry.hasEx = true
            default: throw GenError("unexpected key \(key) in record \(name)")
            }
            keysSeen.insert(key)
            i = afterValue
        }
        guard closed else { throw GenError("unterminated record \(name)") }
        let required: Set<String> = ["n", "d", "p", "s", "r", "pr", "ex"]
        guard keysSeen == required else {
            throw GenError("record \(name) keys \(keysSeen.sorted()) != required")
        }
        entries.append(entry)
        search = i
    }
    return entries
}

// MARK: - Corpus scan (token-aware, Regex-free)

let nameChars = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-*?/+=<>:.$!%&@")

func containsToken(_ text: String, _ name: String) -> Bool {
    var search = text.startIndex
    while let found = text.range(of: name, range: search..<text.endIndex) {
        let beforeOK: Bool = {
            guard found.lowerBound > text.startIndex else { return true }
            return !nameChars.contains(text[text.index(before: found.lowerBound)])
        }()
        let afterOK: Bool = {
            guard found.upperBound < text.endIndex else { return true }
            return !nameChars.contains(text[found.upperBound])
        }()
        if beforeOK, afterOK { return true }
        search = found.upperBound
    }
    return false
}

// MARK: - Swift literal emission (JSON escaping is valid Swift)

func swiftLiteral(_ value: String) -> String {
    let data = try! JSONSerialization.data(
        withJSONObject: ["v": value], options: [.sortedKeys, .withoutEscapingSlashes])
    let json = String(data: data, encoding: .utf8)!
    // {"v":"..."} -> "..."
    let start = json.index(json.startIndex, offsetBy: 5)
    let end = json.index(json.endIndex, offsetBy: -1)
    return String(json[start..<end])
}

struct GenError: Error, CustomStringConvertible {
    let message: String
    init(_ message: String) { self.message = message }
    var description: String { message }
}

// MARK: - Main

func run() throws {
    var input = ""
    var corpus = ""
    var output = ""
    var args = CommandLine.arguments.dropFirst()
    while let arg = args.first {
        args = args.dropFirst()
        switch arg {
        case "--input": input = args.first ?? ""; args = args.dropFirst()
        case "--corpus": corpus = args.first ?? ""; args = args.dropFirst()
        case "--output": output = args.first ?? ""; args = args.dropFirst()
        default: throw GenError("unknown argument \(arg)")
        }
    }
    guard !input.isEmpty, !corpus.isEmpty, !output.isEmpty else {
        throw GenError("usage: LispGen --input <autolisp.html> --corpus <dir> --output <file.swift>")
    }
    let html: String
    do { html = try String(contentsOfFile: input, encoding: .utf8) }
    catch { throw GenError("cannot read input \(input): \(error)") }

    let entries = try scanRecords(html)
    guard entries.count == 305 else {
        throw GenError("expected 305 records, found \(entries.count)")
    }
    let names = entries.map(\.n)
    guard Set(names).count == names.count else {
        let dupes = Dictionary(grouping: names, by: { $0 }).filter { $1.count > 1 }.keys.sorted()
        throw GenError("duplicate entries: \(dupes)")
    }
    let inventory = Set(names)
    for name in stubNames.union(waveACoreNames) where !inventory.contains(name) {
        throw GenError("policy name not in inventory: \(name)")
    }

    // Corpus scan.
    let corpusFiles = try FileManager.default.contentsOfDirectory(atPath: corpus)
        .filter { $0.hasSuffix(".lsp") }.sorted()
    guard !corpusFiles.isEmpty else { throw GenError("no .lsp files in \(corpus)") }
    var corpusText = ""
    for file in corpusFiles {
        corpusText += (try String(contentsOfFile: corpus + "/" + file, encoding: .utf8)) + "\n"
    }
    let referenced = Set(names.filter { containsToken(corpusText, $0) })
    let stubbedButReferenced = referenced.intersection(stubNames)
    guard stubbedButReferenced.isEmpty else {
        throw GenError("corpus references stubbed builtins: \(stubbedButReferenced.sorted())")
    }

    // Dispositions.
    func disposition(of entry: RawEntry) -> Disposition {
        if stubNames.contains(entry.n) { return .stub }
        if waveACoreNames.contains(entry.n) { return .waveA }
        if referenced.contains(entry.n) { return .waveA } // corpus promotion
        if entry.p.contains("Web") { return .waveB }
        return .waveC
    }
    let promoted = referenced.subtracting(waveACoreNames).subtracting(stubNames).sorted()
    var counts: [Disposition: Int] = [.waveA: 0, .waveB: 0, .waveC: 0, .stub: 0]
    for entry in entries { counts[disposition(of: entry), default: 0] += 1 }

    // Emit.
    var swift = """
    // LispRegistry.generated.swift — DO NOT EDIT.
    // Generated by LispGen from Tools/lisp/autolisp.html + Tools/lisp/corpus.
    // Regenerate: swift run LispGen --input Tools/lisp/autolisp.html \\
    //   --corpus Tools/lisp/corpus --output Sources/ZephyrLisp/Generated/LispRegistry.generated.swift

    /// Implementation wave for one AutoLISP builtin.
    public enum LispDisposition: String, Sendable, CaseIterable {
        /// Interactive core + language core + corpus-referenced builtins.
        case waveA
        /// Remaining portable (Windows/Mac/Web) builtins.
        case waveB
        /// Platform-conditional builtins with a portable Zephyr mapping.
        case waveC
        /// No portable implementation: clean-error stub + test.
        case stub
    }

    /// One inventoried AutoLISP builtin: documentation plus disposition.
    public struct LispBuiltinDescriptor: Sendable {
        public let name: String
        public let signature: String
        public let returns: String
        public let params: String
        public let example: String
        public let platforms: String
        public let summary: String
        public let disposition: LispDisposition

        public init(
            name: String, signature: String, returns: String, params: String,
            example: String, platforms: String, summary: String,
            disposition: LispDisposition
        ) {
            self.name = name
            self.signature = signature
            self.returns = returns
            self.params = params
            self.example = example
            self.platforms = platforms
            self.summary = summary
            self.disposition = disposition
        }
    }

    /// The full 305-entry AutoLISP inventory. Order matches the source.
    public enum LispRegistry {
        public static let expectedCount = 305
        public static let all: [LispBuiltinDescriptor] = [

    """
    for entry in entries {
        swift += "        LispBuiltinDescriptor(\n"
        swift += "            name: \(swiftLiteral(entry.n)),\n"
        swift += "            signature: \(swiftLiteral(entry.s)),\n"
        swift += "            returns: \(swiftLiteral(entry.r)),\n"
        swift += "            params: \(swiftLiteral(entry.pr)),\n"
        swift += "            example: \(swiftLiteral(entry.ex)),\n"
        swift += "            platforms: \(swiftLiteral(entry.p)),\n"
        swift += "            summary: \(swiftLiteral(entry.d)),\n"
        swift += "            disposition: .\(disposition(of: entry).rawValue)\n"
        swift += "        ),\n"
    }
    swift += "        ]\n"
    swift += "}\n"
    try swift.write(toFile: output, atomically: true, encoding: .utf8)

    print("records=305 unique=305 corpusFiles=\(corpusFiles.count) " +
        "referenced=\(referenced.count) promoted=\(promoted.count)")
    print("waveA=\(counts[.waveA]!) waveB=\(counts[.waveB]!) " +
        "waveC=\(counts[.waveC]!) stub=\(counts[.stub]!)")
    print("promoted: \(promoted.joined(separator: ","))")
    print("wrote \(output)")
}

do {
    try run()
} catch {
    FileHandle.standardError.write(Data("LispGen: \(error)\n".utf8))
    exit(1)
}
