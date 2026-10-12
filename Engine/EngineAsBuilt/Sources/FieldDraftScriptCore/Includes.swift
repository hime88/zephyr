import Foundation

// MARK: - Include Resolution

public struct FieldDraftScriptFileError: Error, CustomStringConvertible {
    public let path: String
    public let underlying: Error
    public init(path: String, underlying: Error) { self.path = path; self.underlying = underlying }

    public var description: String {
        if let scriptError = underlying as? FieldDraftScriptError {
            return "\(path):\(scriptError)"
        }
        return "\(path): \(underlying)"
    }
}

/// Resolves include directives and loads source from disk.
public enum IncludeResolver {

    /// Load a single .fdscript file, resolving all include directives recursively.
    public static func loadSource(at url: URL, loaded: inout Set<String>) throws -> String {
        let normalized = url.standardizedFileURL
        let key = normalized.path

        if loaded.contains(key) { return "" }
        loaded.insert(key)

        let source = try String(contentsOf: normalized, encoding: .utf8)
        let baseURL = normalized.deletingLastPathComponent()
        var output: [String] = []

        for line in source.components(separatedBy: .newlines) {
            if let includePath = parseIncludePath(from: line) {
                let includeURL = baseURL.appendingPathComponent(includePath).standardizedFileURL

                guard FileManager.default.fileExists(atPath: includeURL.path) else {
                    throw FieldDraftScriptError.parse("Included file not found: \(includePath)", 1, 1)
                }
                output.append(try loadSource(at: includeURL, loaded: &loaded))
            } else {
                output.append(line)
            }
        }
        return output.joined(separator: "\n")
    }

    /// Parse an include directive line. Returns the path inside quotes, or nil.
    public static func parseIncludePath(from line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("include") else { return nil }

        var rest = trimmed.dropFirst("include".count)
        rest = rest.drop(while: { $0 == " " || $0 == "\t" })

        guard rest.first == "\"" else { return nil }
        rest = rest.dropFirst()
        guard let closingQuote = rest.firstIndex(of: "\"") else { return nil }
        return String(rest[..<closingQuote])
    }
}
