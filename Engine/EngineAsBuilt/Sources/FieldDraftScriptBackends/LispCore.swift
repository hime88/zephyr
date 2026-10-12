import Foundation

// MARK: - Core Protocols & Environment

extension String {
    func indent(spaces: Int = 2) -> String {
        let prefix = String(repeating: " ", count: spaces)
        return self.split(separator: "\n", omittingEmptySubsequences: false)
            .map { prefix + $0 }
            .joined(separator: "\n")
    }
}

class LispEnvironment {
    var localVariables: Set<String> = []
}

protocol LispValue {
    func toLispNode() -> LispNode
}

protocol LispNode: LispValue {
    func render(environment: LispEnvironment) -> String
}

extension LispNode {
    func toLispNode() -> LispNode { self }
}

extension String: LispValue {
    func toLispNode() -> LispNode { RawLispNode("\"\(self)\"") }
}

extension Int: LispValue {
    func toLispNode() -> LispNode { RawLispNode("\(self)") }
}

extension Double: LispValue {
    func toLispNode() -> LispNode { RawLispNode("\(self)") }
}

extension LispValue {
    func comment(_ text: String) -> InlineComment {
        InlineComment(self, text)
    }
}

protocol LispType: LispNode {}
protocol LispPointType: LispType {}
protocol LispNumberType: LispType {}
protocol LispStringType: LispType {}
